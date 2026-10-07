package dev.tandem.feature.files

import com.google.protobuf.ByteString
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.FileCancel
import dev.tandem.protocol.v1.FileResumeRequest
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.fileCancel
import dev.tandem.protocol.v1.fileChunk
import dev.tandem.protocol.v1.fileComplete
import dev.tandem.protocol.v1.fileOffer
import dev.tandem.protocol.v1.fileReject
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
import kotlinx.coroutines.flow.update
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

/**
 * Sends that outlive their session (E40-08), so a sender on a reconnected session can resume them.
 * Hold exactly one per paired peer and pass it to every [FileSender] for that peer: a resume is
 * only honoured for ids this peer was offered. Holds at most [MAX_RETAINED] sends, oldest evicted first.
 */
class RetainedSends {
    private val entries = LinkedHashMap<String, Retained>()

    @Synchronized
    internal fun put(
        request: SendRequest,
        size: Long,
    ) {
        entries.remove(request.id)
        entries[request.id] = Retained(request, size)
        while (entries.size > MAX_RETAINED) entries.remove(entries.keys.first())
    }

    @Synchronized
    internal fun find(id: String): Retained? = entries[id]

    @Synchronized
    internal fun remove(id: String) {
        entries.remove(id)
    }

    internal class Retained(
        val request: SendRequest,
        val size: Long,
    )

    private companion object {
        const val MAX_RETAINED = 64
    }
}

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
 *
 * Resume (E40-08; SPEC.md "Resume semantics"): a transfer cut off by a lost session stays in
 * [retained] (kept after the last chunk too: chunks may be in flight when the session drops).
 * `FileResumeRequest{id, fromOffset}` for a retained id seeks the source to a
 * chunk-aligned `fromOffset <= size` and streams from `seq = fromOffset / 262144`; an unknown id
 * answers `FileReject UNKNOWN_TRANSFER`, an unreadable source `SOURCE_UNAVAILABLE`, a misaligned
 * or oversized offset `PROTOCOL_VIOLATION`.
 *
 * Cancel (E40-09): [cancelTransfer] sends `FileCancel USER_CANCELLED`, stops reading and sending
 * (no chunk follows the cancel) and forgets the id in [retained], so a later resume for it
 * answers `FileReject UNKNOWN_TRANSFER`. A peer `FileCancel` while streaming does the same.
 */
@Suppress("TooManyFunctions") // sender protocol steps, kept together to share state
class FileSender(
    private val session: TandemSession,
    private val scheduler: FilesScheduler,
    private val reader: SourceFileReader,
    private val ioDispatcher: CoroutineDispatcher,
    dispatcher: CoroutineDispatcher,
    private val retained: RetainedSends = RetainedSends(),
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val replies = ConcurrentHashMap<String, CompletableDeferred<Reply>>()
    private val peerCancels = ConcurrentHashMap<String, TransferReason>()
    private val states = ConcurrentHashMap<String, MutableStateFlow<SenderState>>()
    private val bytes = MutableStateFlow<Map<String, TransferBytes>>(emptyMap())

    /** Bytes sent so far per in-flight transfer id (E40-12). */
    val progress: StateFlow<Map<String, TransferBytes>> = bytes.asStateFlow()

    init {
        session
            .receive(Channel.CHANNEL_FILES)
            .onEach { envelope ->
                when {
                    envelope.hasFileAccept() -> {
                        FilesLog.event("accept received")
                        replies[envelope.fileAccept.id]?.complete(Reply.Accepted)
                    }

                    envelope.hasFileReject() -> {
                        val reject = envelope.fileReject
                        FilesLog.event("reject received", reject.reason)
                        replies[reject.id]?.complete(Reply.Rejected(reject.reason))
                    }

                    envelope.hasFileCancel() -> {
                        val cancel = envelope.fileCancel
                        if (states.containsKey(cancel.id)) peerCancels[cancel.id] = cancel.reason
                        replies[cancel.id]?.complete(Reply.Cancelled(cancel.reason))
                    }

                    envelope.hasFileResumeRequest() -> {
                        val resume = envelope.fileResumeRequest
                        scope.launch { resume(resume) }
                    }
                }
            }.launchIn(scope)
    }

    fun send(request: SendRequest): StateFlow<SenderState> {
        val state = MutableStateFlow<SenderState>(SenderState.Hashing)
        states[request.id] = state
        scope.launch {
            try {
                run(request, state)
            } catch (_: MultiplexerClosedException) {
                state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_IO_ERROR)
            } finally {
                replies.remove(request.id)
                peerCancels.remove(request.id)
                states.remove(request.id)
            }
        }
        return state.asStateFlow()
    }

    /** User-initiated cancel of the send [id]; no-op for an id that is not in flight. */
    fun cancelTransfer(id: String) {
        scope.launch {
            val state = states[id]?.takeUnless { it.value is SenderState.Completed } ?: return@launch
            peerCancels[id] = TransferReason.TRANSFER_REASON_USER_CANCELLED
            retained.remove(id)
            if (state.value == SenderState.Hashing) return@launch
            refuse(id, TransferReason.TRANSFER_REASON_USER_CANCELLED)
            replies[id]?.complete(Reply.Cancelled(TransferReason.TRANSFER_REASON_USER_CANCELLED))
        }
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
                FilesLog.event("send failed: source unreadable")
                state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_SOURCE_UNAVAILABLE)
                return
            }
        val userCancel = peerCancels[request.id]
        if (userCancel != null) {
            state.value = SenderState.Cancelled(userCancel)
            return
        }
        retained.put(request, source.size)
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
        FilesLog.event("offer sent")
        state.value = SenderState.Offered
        when (val answer = reply.await()) {
            is Reply.Rejected -> {
                retained.remove(request.id)
                state.value = SenderState.Rejected(answer.reason)
            }

            is Reply.Cancelled -> {
                retained.remove(request.id)
                state.value = SenderState.Cancelled(answer.reason)
            }

            Reply.Accepted -> {
                stream(request, state, source.size)
            }
        }
    }

    private suspend fun stream(
        request: SendRequest,
        state: MutableStateFlow<SenderState>,
        size: Long,
    ) {
        state.value = SenderState.Sending
        val input =
            try {
                withContext(ioDispatcher) { reader.open(request.uri) }
            } catch (_: IOException) {
                cancel(request.id, state)
                return
            }
        try {
            input.use { scheduler.run(ChunkStream(request.id, it, state, startSeq = 0, size = size)) }
        } finally {
            bytes.update { it - request.id }
        }
    }

    private suspend fun resume(resume: FileResumeRequest) {
        val known = retained.find(resume.id)
        when {
            replies.containsKey(resume.id) -> {
                Unit
            }

            known == null -> {
                rejectUnknown(resume.id)
            }

            resume.fromOffset < 0 || resume.fromOffset % CHUNK_BYTES != 0L || resume.fromOffset > known.size -> {
                refuse(resume.id, TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
            }

            else -> {
                resumeStream(known, resume.fromOffset)
            }
        }
    }

    private suspend fun resumeStream(
        known: RetainedSends.Retained,
        fromOffset: Long,
    ) {
        val id = known.request.id
        val input =
            try {
                withContext(ioDispatcher) { reader.open(known.request.uri).also { it.skipOrClose(fromOffset) } }
            } catch (_: IOException) {
                return refuse(id, TransferReason.TRANSFER_REASON_SOURCE_UNAVAILABLE)
            }
        replies[id] = CompletableDeferred()
        val state = MutableStateFlow<SenderState>(SenderState.Sending)
        states[id] = state
        try {
            input.use {
                scheduler.run(
                    ChunkStream(id, it, state, startSeq = fromOffset / CHUNK_BYTES, size = known.size),
                )
            }
        } catch (_: MultiplexerClosedException) {
            return
        } finally {
            replies.remove(id)
            peerCancels.remove(id)
            states.remove(id)
            bytes.update { it - id }
        }
    }

    private suspend fun rejectUnknown(id: String) {
        try {
            scheduler.sendPriority {
                fileReject =
                    fileReject {
                        this.id = id
                        reason = TransferReason.TRANSFER_REASON_UNKNOWN_TRANSFER
                    }
            }
        } catch (_: MultiplexerClosedException) {
            return
        }
    }

    private suspend fun refuse(
        id: String,
        why: TransferReason,
    ) {
        try {
            scheduler.sendPriority {
                fileCancel =
                    fileCancel {
                        this.id = id
                        reason = why
                    }
            }
        } catch (_: MultiplexerClosedException) {
            return
        }
    }

    private fun InputStream.skipOrClose(count: Long) {
        try {
            var left = count
            while (left > 0) left -= skipSome(left)
        } catch (e: IOException) {
            close()
            throw e
        }
    }

    private fun InputStream.skipSome(left: Long): Long {
        val skipped = skip(left)
        if (skipped > 0) return skipped
        if (read() < 0) throw IOException("source shorter than resume offset")
        return 1
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
        startSeq: Long,
        private val size: Long,
    ) : FrameStream {
        private val buffer = ByteArray(CHUNK_BYTES)
        private var seq = startSeq

        override suspend fun sendNext(): Boolean {
            if (stoppedByCancel()) return false
            val read = readChunk()
            return when {
                read == null -> {
                    session.send(Channel.CHANNEL_FILES) { fileCancel = ioErrorCancel(id) }
                    state.value = SenderState.Cancelled(TransferReason.TRANSFER_REASON_IO_ERROR)
                    false
                }

                read == 0 -> {
                    session.send(Channel.CHANNEL_FILES) { fileComplete = fileComplete { id = this@ChunkStream.id } }
                    FilesLog.event("transfer complete")
                    state.value = SenderState.Completed
                    false
                }

                else -> {
                    sendChunk(checkNotNull(read))
                    true
                }
            }
        }

        private fun stoppedByCancel(): Boolean {
            val cancel = peerCancels[id] ?: return false
            retained.remove(id)
            state.value = SenderState.Cancelled(cancel)
            return true
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
            bytes.update { it + (id to TransferBytes(chunkSeq * CHUNK_BYTES + length, size)) }
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
