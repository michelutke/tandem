package dev.tandem.core.transport

import dev.tandem.core.protocol.FrameTooLargeException
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.EnvelopeKt
import kotlinx.coroutines.CoroutineExceptionHandler

/**
 * [TandemSession.send] for fire-and-forget callers: a session that closed in the meantime, or a
 * frame over the envelope limit, drops this one message and returns `false` instead of throwing, so
 * it can neither crash a handler-less scope nor end the caller's collector for the rest of the
 * session.
 */
@Suppress("SwallowedException") // nothing is left to deliver the message to, or the message cannot be sent
suspend fun TandemSession.sendOrDrop(
    channel: Channel,
    payload: EnvelopeKt.Dsl.() -> Unit,
): Boolean =
    try {
        send(channel, payload)
        true
    } catch (_: MultiplexerClosedException) {
        false
    } catch (_: FrameTooLargeException) {
        false
    }

/**
 * Exception handler for root scopes whose coroutines send on a [TandemSession]: a send that finds
 * the session closed, or a frame over the envelope limit, ends only the coroutine that made it.
 * Every other uncaught exception still reaches the thread's uncaught-exception handler.
 */
val SessionSendFailureHandler: CoroutineExceptionHandler =
    CoroutineExceptionHandler { _, throwable ->
        if (throwable !is MultiplexerClosedException && throwable !is FrameTooLargeException) {
            val thread = Thread.currentThread()
            thread.uncaughtExceptionHandler.uncaughtException(thread, throwable)
        }
    }
