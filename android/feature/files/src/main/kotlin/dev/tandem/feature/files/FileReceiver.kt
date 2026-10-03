package dev.tandem.feature.files

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.PeerDataPurging
import dev.tandem.core.protocol.FilenameSanitizer
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.FileChunk
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.fileCancel
import dev.tandem.protocol.v1.fileReject
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Receiver half of a FILES transfer after `FileAccept` (E40-05; SPEC.md #files-channel "Chunking").
 * [expect] registers an accepted offer. Each chunk must start at the current length, stay within
 * the offered size and be <= 256 KiB, else `FileCancel PROTOCOL_VIOLATION`; bytes go to
 * [store] (app-private) and a running SHA-256. On `FileComplete` the length and digest are
 * checked before [publisher] sees the file: a digest mismatch sends `FileCancel HASH_MISMATCH`.
 * The `.part` file is deleted on every failure and cancel. Disk I/O runs on [ioDispatcher]; state
 * is confined to [dispatcher], which MUST be single-threaded. Invariant 7: never logs names or content.
 */
class FileReceiver(
    private val session: TandemSession,
    private val store: TransferStore,
    private val publisher: DownloadsPublisher,
    private val ioDispatcher: CoroutineDispatcher,
    private val dispatcher: CoroutineDispatcher,
) : PeerDataPurging {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val transfers = ConcurrentHashMap<String, Transfer>()

    /** Number of accepted transfers still receiving; feeds AcceptFlow's `activeTransfers`. */
    val activeCount: Int get() = transfers.size

    init {
        session
            .receive(Channel.CHANNEL_FILES)
            .onEach { envelope ->
                when {
                    envelope.hasFileChunk() -> onChunk(envelope.fileChunk)
                    envelope.hasFileComplete() -> onComplete(envelope.fileComplete.id)
                    envelope.hasFileCancel() -> discard(envelope.fileCancel.id)
                }
            }.launchIn(scope)
    }

    fun expect(offer: FileOffer) {
        scope.launch {
            val name = FilenameSanitizer.sanitize(offer.name, offer.id) ?: return@launch
            transfers[offer.id] = Transfer(offer, name, MessageDigest.getInstance(SHA_256))
            try {
                withContext(ioDispatcher) { store.create(offer.id) }
            } catch (_: IOException) {
                fail(offer.id, TransferReason.TRANSFER_REASON_IO_ERROR)
            }
        }
    }

    override suspend fun purgeAll(peerFingerprint: SpkiFingerprint) {
        withContext(dispatcher) { transfers.clear() }
        withContext(ioDispatcher) { store.deleteAll() }
    }

    fun close() {
        scope.cancel()
    }

    private suspend fun onChunk(chunk: FileChunk) {
        val transfer = transfers[chunk.id] ?: return reject(chunk.id, TransferReason.TRANSFER_REASON_UNKNOWN_TRANSFER)
        val bytes = chunk.data.toByteArray()
        val violates =
            bytes.size > MAX_CHUNK_BYTES ||
                chunk.offset != transfer.received ||
                chunk.offset + bytes.size > transfer.offer.size
        val failure =
            if (violates) {
                TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION
            } else {
                try {
                    withContext(ioDispatcher) { store.append(chunk.id, bytes) }
                    null
                } catch (_: InsufficientSpaceException) {
                    TransferReason.TRANSFER_REASON_INSUFFICIENT_SPACE
                } catch (_: IOException) {
                    TransferReason.TRANSFER_REASON_IO_ERROR
                }
            }
        if (failure != null) return fail(chunk.id, failure)
        transfer.digest.update(bytes)
        transfer.received += bytes.size
    }

    private suspend fun onComplete(id: String) {
        val transfer = transfers[id] ?: return reject(id, TransferReason.TRANSFER_REASON_UNKNOWN_TRANSFER)
        val digestMatches = MessageDigest.isEqual(transfer.digest.digest(), transfer.offer.sha256.toByteArray())
        when {
            transfer.received != transfer.offer.size -> {
                fail(id, TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
            }

            !digestMatches -> {
                fail(id, TransferReason.TRANSFER_REASON_HASH_MISMATCH)
            }

            else -> {
                publish(transfer)
            }
        }
    }

    private suspend fun publish(transfer: Transfer) {
        val id = transfer.offer.id
        try {
            withContext(ioDispatcher) {
                store.open(id).use { publisher.publish(transfer.name, transfer.offer.mime, it) }
            }
        } catch (_: IOException) {
            return fail(id, TransferReason.TRANSFER_REASON_IO_ERROR)
        }
        discard(id)
    }

    private suspend fun fail(
        id: String,
        why: TransferReason,
    ) {
        discard(id)
        send {
            fileCancel =
                fileCancel {
                    this.id = id
                    reason = why
                }
        }
    }

    private suspend fun reject(
        id: String,
        why: TransferReason,
    ) {
        send {
            fileReject =
                fileReject {
                    this.id = id
                    reason = why
                }
        }
    }

    private suspend fun discard(id: String) {
        transfers.remove(id)
        withContext(ioDispatcher) { store.delete(id) }
    }

    private suspend fun send(payload: EnvelopeKt.Dsl.() -> Unit) {
        try {
            session.send(Channel.CHANNEL_FILES, payload)
        } catch (_: MultiplexerClosedException) {
            return
        }
    }

    private class Transfer(
        val offer: FileOffer,
        val name: String,
        val digest: MessageDigest,
        var received: Long = 0,
    )

    private companion object {
        const val SHA_256 = "SHA-256"
        const val MAX_CHUNK_BYTES = 262_144
    }
}
