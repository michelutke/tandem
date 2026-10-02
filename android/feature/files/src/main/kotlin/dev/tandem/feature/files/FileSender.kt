package dev.tandem.feature.files

import com.google.protobuf.ByteString
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.FileCancel
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.fileCancel
import dev.tandem.protocol.v1.fileChunk
import dev.tandem.protocol.v1.fileComplete
import dev.tandem.protocol.v1.fileOffer
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/** What to send: [uri] is opened through [SourceFileReader]; [name] and [mime] go into the FileOffer. */
data class SendRequest(
    val id: String,
    val uri: String,
    val name: String,
    val mime: String,
)

sealed interface SenderState {
    data object Hashing : SenderState

    data object Offered : SenderState

    data object Sending : SenderState

    data object Completed : SenderState

    data class Rejected(
        val reason: TransferReason,
    ) : SenderState

    data class Cancelled(
        val reason: TransferReason,
    ) : SenderState
}

/**
 * Sender half of a FILES transfer (E40-03; SPEC.md #files-channel "Handshake" and "Chunking"):
 * one streaming SHA-256 pass, `FileOffer` with the digest and measured size, then on `FileAccept`
 * 256 KiB chunks (`offset = seq * 262144`) through [scheduler], then `FileComplete`. A source read
 * failure after the offer sends `FileCancel IO_ERROR`. Reads run on [ioDispatcher]; protocol state
 * is confined to [dispatcher], which MUST be single-threaded. Invariant 7: never logs names or content.
 */
class FileSender(
    private val session: TandemSession,
    private val scheduler: FilesScheduler,
    private val reader: SourceFileReader,
    private val ioDispatcher: CoroutineDispatcher,
    dispatcher: CoroutineDispatcher,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val replies = ConcurrentHashMap<String, CompletableDeferred<Reply>>()
    private val peerCancels = ConcurrentHashMap<String, TransferReason>()

    init {
        session
            .receive(Channel.CHANNEL_FILES)
            .onEach { envelope ->
                when {
                    envelope.hasFileAccept() -> {
                        replies[envelope.fileAccept.id]?.complete(Reply.Accepted)
                    }

                    envelope.hasFileReject() -> {
                        val reject = envelope.fileReject
                        replies[reject.id]?.complete(Reply.Rejected(reject.reason))
                    }

                    envelope.hasFileCancel() -> {
                        val cancel = envelope.fileCancel
                        if (replies.containsKey(cancel.id)) peerCancels[cancel.id] = cancel.reason
                        replies[cancel.id]?.complete(Reply.Cancelled(cancel.reason))
                    }
                }
            }.launchIn(scope)
    }

    fun send(request: SendRequest): StateFlow<SenderState> {
        val state = MutableStateFlow<SenderState>(SenderState.Hashing)
        scope.launch {
            try {
                run(request, state)
            } catch (_: MultiplexerClosedException) {
                state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_IO_ERROR)
            } finally {
                replies.remove(request.id)
                peerCancels.remove(request.id)
            }
        }
        return state.asStateFlow()
    }

    fun close() {
        scope.cancel()
    }

    private suspend fun run(
        request: SendRequest,
        state: MutableStateFlow<SenderState>,
    ) {
        val source =
            try {
                withContext(ioDispatcher) { hash(request.uri) }
            } catch (_: IOException) {
                state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_SOURCE_UNAVAILABLE)
                return
            }
        val reply = CompletableDeferred<Reply>().also { replies[request.id] = it }
        scheduler.sendPriority {
            fileOffer =
                fileOffer {
                    id = request.id
                    name = request.name
                    size = source.size
                    mime = request.mime
                    sha256 = ByteString.copyFrom(source.sha256)
                }
        }
        state.value = SenderState.Offered
        when (val answer = reply.await()) {
            is Reply.Rejected -> state.value = SenderState.Rejected(answer.reason)
            is Reply.Cancelled -> state.value = SenderState.Cancelled(answer.reason)
            Reply.Accepted -> stream(request, state)
        }
    }

    private suspend fun stream(
        request: SendRequest,
        state: MutableStateFlow<SenderState>,
    ) {
        state.value = SenderState.Sending
        val input =
            try {
                withContext(ioDispatcher) { reader.open(request.uri) }
            } catch (_: IOException) {
                cancel(request.id, state)
                return
            }
        input.use { scheduler.run(ChunkStream(request.id, it, state)) }
    }

    private suspend fun cancel(
        id: String,
        state: MutableStateFlow<SenderState>,
    ) {
        scheduler.sendPriority { fileCancel = ioErrorCancel(id) }
        state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_IO_ERROR)
    }

    private fun hash(uri: String): HashedSource {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(CHUNK_BYTES)
        var size = 0L
        reader.open(uri).use { input ->
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
                size += read
            }
        }
        return HashedSource(digest.digest(), size)
    }

    private inner class ChunkStream(
        private val id: String,
        private val input: InputStream,
        private val state: MutableStateFlow<SenderState>,
    ) : FrameStream {
        private val buffer = ByteArray(CHUNK_BYTES)
        private var seq = 0L

        override suspend fun sendNext(): Boolean {
            val peerCancel = peerCancels[id]
            if (peerCancel != null) {
                state.value = SenderState.Cancelled(peerCancel)
                return false
            }
            val read = readChunk()
            return when (read) {
                null -> {
                    session.send(Channel.CHANNEL_FILES) { fileCancel = ioErrorCancel(id) }
                    state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_IO_ERROR)
                    false
                }

                0 -> {
                    session.send(Channel.CHANNEL_FILES) { fileComplete = fileComplete { id = this@ChunkStream.id } }
                    state.value = SenderState.Completed
                    false
                }

                else -> {
                    sendChunk(read)
                    true
                }
            }
        }

        private suspend fun readChunk(): Int? =
            try {
                withContext(ioDispatcher) { fillBuffer() }
            } catch (_: IOException) {
                null
            }

        private fun fillBuffer(): Int {
            var filled = 0
            while (filled < CHUNK_BYTES) {
                val read = input.read(buffer, filled, CHUNK_BYTES - filled)
                if (read < 0) break
                filled += read
            }
            return filled
        }

        private suspend fun sendChunk(length: Int) {
            val chunkSeq = seq++
            session.send(Channel.CHANNEL_FILES) {
                fileChunk =
                    fileChunk {
                        id = this@ChunkStream.id
                        this.seq = chunkSeq
                        offset = chunkSeq * CHUNK_BYTES
                        data = ByteString.copyFrom(buffer, 0, length)
                    }
            }
        }
    }

    private class HashedSource(
        val sha256: ByteArray,
        val size: Long,
    )

    private sealed interface Reply {
        data object Accepted : Reply

        data class Cancelled(
            val reason: TransferReason,
        ) : Reply

        data class Rejected(
            val reason: TransferReason,
        ) : Reply
    }

    private companion object {
        const val CHUNK_BYTES = 262_144

        fun ioErrorCancel(transferId: String): FileCancel =
            fileCancel {
                id = transferId
                reason = TransferReason.TRANSFER_REASON_IO_ERROR
            }
    }
}
