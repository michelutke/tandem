package dev.tandem.feature.notifications

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The real, session-facing [NotificationEventSink] (E30-16; SPEC.md F-5.1's disconnected-buffer
 * policy, split from E30-02 in backlog review cycle 3): while [session] is not
 * [ConnectionState.Ready], holds posted notifications in memory only -- at most [MAX_BUFFERED]
 * entries, oldest dropped first, each evicted once older than [MAX_AGE_MILLIS] -- and flushes them
 * oldest-first the moment the session becomes [ConnectionState.Ready]. While already
 * [ConnectionState.Ready], a post is sent immediately, never buffered.
 *
 * A dismiss for a still-buffered key removes it from the buffer without ever sending either the
 * post or the dismiss (SPEC acceptance): the phone showed and then withdrew the notification
 * before the Mac was ever told about it, so there is nothing for the Mac to withdraw. A dismiss
 * for a key that isn't buffered is sent immediately if [ConnectionState.Ready], and otherwise
 * dropped -- it refers to a notification already sent (and thus not held here) before the
 * connection dropped; buffering the dismiss itself is out of this issue's specified scope.
 *
 * Age uses the injected [ElapsedRealtimeSource] (E00-18, sleep-inclusive) rather than wall time,
 * matching every other duration measurement in this codebase. Every buffer read/mutation holds
 * [bufferLock], since [TandemNotificationListenerService]'s callbacks and [session]'s state
 * collection are not guaranteed to run on the same thread even when [dispatcher] happens to be
 * single-threaded.
 *
 * Invariant 7 (CLAUDE.md): this class never logs a [NotificationPosted]/[NotificationDismiss] or
 * any of their fields.
 */
class NotificationSink(
    private val session: TandemSession,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    dispatcher: CoroutineDispatcher,
) : NotificationEventSink {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    private val bufferLock = Mutex()

    // Oldest first. Only ever touched while holding [bufferLock].
    private val buffer = ArrayDeque<BufferedPost>()

    init {
        scope.launch {
            session.state.collect { state ->
                if (state is ConnectionState.Ready) flush()
            }
        }
    }

    /** Stops observing [session]'s state. Callers replacing this instance MUST call this first --
     * an un-closed instance keeps reacting to [session]'s state indefinitely, which would race a
     * replacement instance over the same session. */
    fun close() {
        scope.cancel()
    }

    override fun onNotificationPosted(notification: NotificationPosted) {
        scope.launch {
            if (session.state.value is ConnectionState.Ready) {
                sendPosted(notification)
                return@launch
            }
            bufferLock.withLock {
                evictExpiredLocked()
                buffer.addLast(BufferedPost(notification, elapsedRealtimeSource.elapsedRealtimeMillis()))
                while (buffer.size > MAX_BUFFERED) {
                    buffer.removeFirst()
                }
            }
        }
    }

    override fun onNotificationDismissed(dismiss: NotificationDismiss) {
        scope.launch {
            val removed = bufferLock.withLock { buffer.removeAll { it.notification.key == dismiss.key } }
            if (!removed && session.state.value is ConnectionState.Ready) {
                session.send(Channel.CHANNEL_NOTIFY) { notificationDismiss = dismiss }
            }
        }
    }

    private suspend fun flush() {
        while (true) {
            val next =
                bufferLock.withLock {
                    evictExpiredLocked()
                    if (buffer.isEmpty()) null else buffer.removeFirst()
                } ?: break
            sendPosted(next.notification)
        }
    }

    /** Caller must hold [bufferLock]. */
    private fun evictExpiredLocked() {
        val now = elapsedRealtimeSource.elapsedRealtimeMillis()
        while (buffer.isNotEmpty() && now - buffer.first().bufferedAtMillis >= MAX_AGE_MILLIS) {
            buffer.removeFirst()
        }
    }

    private suspend fun sendPosted(notification: NotificationPosted) {
        session.send(Channel.CHANNEL_NOTIFY) { notificationPosted = notification }
    }

    private data class BufferedPost(
        val notification: NotificationPosted,
        val bufferedAtMillis: Long,
    )

    private companion object {
        const val MAX_BUFFERED = 50
        const val MAX_AGE_MILLIS = 60_000L
    }
}
