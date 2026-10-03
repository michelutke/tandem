package dev.tandem.feature.files

import com.google.protobuf.InvalidProtocolBufferException
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
import dev.tandem.protocol.v1.fileResumeRequest
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.time.Clock
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.hours

/**
 * Receiver half of a FILES transfer after `FileAccept` (E40-05; SPEC.md #files-channel "Chunking").
 * [expect] registers an accepted offer. Each chunk must start at the current length, stay within
 * the offered size and be <= 256 KiB, else `FileCancel PROTOCOL_VIOLATION`; bytes go to
 * [store] (app-private) and a running SHA-256. On `FileComplete` the length and digest are
 * checked before [publisher] sees the file: a digest mismatch sends `FileCancel HASH_MISMATCH`.
 * The `.part` file is deleted on every failure and cancel. Disk I/O runs on [ioDispatcher]; state
 * is confined to [dispatcher], which MUST be single-threaded. Invariant 7: never logs names or content.
 *
 * Resume (E40-08; SPEC.md "Resume semantics"): each `.part` file keeps its offer and the [peer]
 * fingerprint as metadata. [resumeRetained] first deletes files whose last write (from [clock]) is
 * over 24 h old, then for every file retained for this [peer]: truncates it to a 256 KiB
 * boundary, re-hashes the retained prefix and sends `FileResumeRequest{id, fromOffset}`. Chunks
 * are still validated against the on-disk length, never against sender-claimed offsets.
 *
 * Cancel (E40-09): [cancelTransfer] and a peer `FileCancel` both delete the `.part` file and
 * publish nothing; a chunk for a cancelled id is answered `FileReject UNKNOWN_TRANSFER`.
 */
@Suppress("TooManyFunctions", "LongParameterList") // receiver steps share state; seams are injected
class FileReceiver(
    private val session: TandemSession,
    private val store: TransferStore,
    private val publisher: DownloadsPublisher,
    private val peer: SpkiFingerprint,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val dispatcher: CoroutineDispatcher,
) : PeerDataPurging {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val transfers = ConcurrentHashMap<String, Transfer>()
    private val bytes = MutableStateFlow<Map<String, TransferBytes>>(emptyMap())

    /** Bytes received so far per accepted transfer id (E40-12). */
    val progress: StateFlow<Map<String, TransferBytes>> = bytes.asStateFlow()

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
                    envelope.hasFileReject() -> discard(envelope.fileReject.id)
                }
            }.launchIn(scope)
    }

    fun expect(offer: FileOffer) {
        scope.launch {
            val name = FilenameSanitizer.sanitize(offer.name, offer.id) ?: return@launch
            transfers[offer.id] = Transfer(offer, name, MessageDigest.getInstance(SHA_256))
            try {
                withContext(ioDispatcher) {
                    store.create(offer.id)
                    store.writeMeta(offer.id, peer.bytes + offer.toByteArray())
                }
            } catch (_: IOException) {
                fail(offer.id, TransferReason.TRANSFER_REASON_IO_ERROR)
            }
        }
    }

    /** User-initiated cancel: deletes the `.part` file, publishes nothing, sends `FileCancel USER_CANCELLED`. */
    fun cancelTransfer(id: String) {
        scope.launch {
            if (transfers.containsKey(id)) fail(id, TransferReason.TRANSFER_REASON_USER_CANCELLED)
        }
    }

    /** Call after (re)connecting: sweeps expired `.part` files and requests resumption of the rest. */
    fun resumeRetained() {
        scope.launch {
            val retained = withContext(ioDispatcher) { sweepExpired().mapNotNull(::loadRetained) }
            retained.filter { !transfers.containsKey(it.offer.id) }.forEach { resume(it) }
        }
    }

    override suspend fun purgeAll(peerFingerprint: SpkiFingerprint) {
        withContext(dispatcher) { transfers.clear() }
        withContext(ioDispatcher) { store.deleteAll() }
    }

    fun close() {
        scope.cancel()
    }

    private fun sweepExpired(): List<String> {
        val now = clock.millis()
        return store.ids().filter { storeId ->
            val expired = now - store.lastWriteMillis(storeId) > RETENTION.inWholeMilliseconds
            if (expired) store.delete(storeId)
            !expired
        }
    }

    private fun loadRetained(storeId: String): Transfer? {
        val meta = store.readMeta(storeId)
        val offer = meta?.let(::parseMeta)
        val name = offer?.let { FilenameSanitizer.sanitize(it.name, it.id) }
        val resumable = offer != null && name != null && store.length(storeId) <= offer.size
        return when {
            meta == null || !resumable -> deleteCorrupt(storeId)
            !metaPeerMatches(meta) -> null
            else -> prepareResume(storeId, checkNotNull(offer), checkNotNull(name))
        }
    }

    private fun deleteCorrupt(storeId: String): Transfer? {
        store.delete(storeId)
        return null
    }

    private fun metaPeerMatches(meta: ByteArray): Boolean =
        MessageDigest.isEqual(meta.copyOfRange(0, peer.bytes.size), peer.bytes)

    private fun parseMeta(meta: ByteArray): FileOffer? =
        if (meta.size <= peer.bytes.size) {
            null
        } else {
            try {
                FileOffer.parseFrom(meta.copyOfRange(peer.bytes.size, meta.size))
            } catch (_: InvalidProtocolBufferException) {
                null
            }
        }

    private fun prepareResume(
        storeId: String,
        offer: FileOffer,
        name: String,
    ): Transfer? =
        try {
            val boundary = store.length(storeId) / MAX_CHUNK_BYTES * MAX_CHUNK_BYTES
            store.truncate(storeId, boundary)
            val digest = MessageDigest.getInstance(SHA_256)
            store.open(storeId).use { input -> digestPrefix(input, digest, boundary) }
            Transfer(offer, name, digest, boundary)
        } catch (_: IOException) {
            deleteCorrupt(storeId)
        }

    private fun digestPrefix(
        input: InputStream,
        digest: MessageDigest,
        length: Long,
    ) {
        val buffer = ByteArray(MAX_CHUNK_BYTES)
        var remaining = length
        while (remaining > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (read < 0) throw IOException("retained file shorter than its length")
            digest.update(buffer, 0, read)
            remaining -= read
        }
    }

    private suspend fun resume(transfer: Transfer) {
        transfers[transfer.offer.id] = transfer
        send {
            fileResumeRequest =
                fileResumeRequest {
                    id = transfer.offer.id
                    fromOffset = transfer.received
                }
        }
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
        this.bytes.update { it + (chunk.id to TransferBytes(transfer.received, transfer.offer.size)) }
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
        bytes.update { it - id }
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
        val RETENTION = 24.hours
    }
}
