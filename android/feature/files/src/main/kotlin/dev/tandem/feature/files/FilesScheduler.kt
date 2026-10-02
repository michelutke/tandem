package dev.tandem.feature.files

import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.EnvelopeKt
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentLinkedQueue
import kotlinx.coroutines.channels.Channel as KtChannel

/** One transfer's outgoing frames: each [sendNext] sends exactly one frame; false once finished. */
fun interface FrameStream {
    suspend fun sendNext(): Boolean
}

/**
 * Single writer for the FILES channel (E40-03; backlog: "round-robin between active transfers
 * and E41 page/thumb responses"). Active [FrameStream]s are advanced one frame at a time in
 * rotation, and every queued [sendPriority] response is flushed before the next frame, so a
 * response is never delayed by more than one chunk. FILES credit gating is [TandemSession.send]'s
 * own suspension. [dispatcher] MUST be single-threaded.
 */
class FilesScheduler(
    private val session: TandemSession,
    dispatcher: CoroutineDispatcher,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val responses = ConcurrentLinkedQueue<Response>()
    private val newStreams = ConcurrentLinkedQueue<ActiveStream>()
    private val rotation = ArrayDeque<ActiveStream>()
    private val wake = KtChannel<Unit>(KtChannel.CONFLATED)

    init {
        scope.launch { run() }
    }

    suspend fun sendPriority(payload: EnvelopeKt.Dsl.() -> Unit) {
        val response = Response(payload)
        responses.add(response)
        wake.trySend(Unit)
        response.done.await()
    }

    suspend fun run(stream: FrameStream) {
        val active = ActiveStream(stream)
        newStreams.add(active)
        wake.trySend(Unit)
        active.done.await()
    }

    fun close() {
        scope.cancel()
    }

    private suspend fun run() {
        while (true) {
            flushResponses()
            while (true) newStreams.poll()?.let { rotation.addLast(it) } ?: break
            val next = rotation.removeFirstOrNull()
            if (next == null) {
                if (responses.isEmpty()) wake.receive()
            } else if (advance(next)) {
                rotation.addLast(next)
            }
        }
    }

    private suspend fun flushResponses() {
        while (true) {
            val response = responses.poll() ?: return
            try {
                session.send(Channel.CHANNEL_FILES, response.payload)
                response.done.complete(Unit)
            } catch (closed: MultiplexerClosedException) {
                response.done.completeExceptionally(closed)
            }
        }
    }

    private suspend fun advance(active: ActiveStream): Boolean =
        try {
            active.stream.sendNext().also { more -> if (!more) active.done.complete(Unit) }
        } catch (closed: MultiplexerClosedException) {
            active.done.completeExceptionally(closed)
            false
        }

    private class Response(
        val payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        val done = CompletableDeferred<Unit>()
    }

    private class ActiveStream(
        val stream: FrameStream,
    ) {
        val done = CompletableDeferred<Unit>()
    }
}
