package dev.tandem.feature.notifications

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted

/**
 * Process-lifetime [NotificationEventSink] (E30-16, SPEC.md F-5.1's disconnected-buffer policy):
 * while no session sink is attached, holds posted notifications in memory only, at most
 * [MAX_BUFFERED] entries (oldest dropped first) and each for at most [MAX_AGE_MILLIS], and hands
 * them oldest-first to the sink that [attach]es next. While attached, every event goes straight to
 * that sink. A dismiss for a still-buffered key removes it without telling anyone; other dismisses
 * and icons are dropped while detached.
 *
 * Invariant 7 (CLAUDE.md): never logs a [NotificationPosted] or any of its fields.
 */
class DisconnectedNotificationBuffer(
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
) : NotificationEventSink {
    private val lock = Any()
    private val buffer = ArrayDeque<BufferedPost>()
    private var attached: NotificationEventSink? = null

    fun attach(sink: NotificationEventSink) {
        synchronized(lock) {
            evictExpired()
            while (buffer.isNotEmpty()) sink.onNotificationPosted(buffer.removeFirst().notification)
            attached = sink
        }
    }

    fun detach() {
        synchronized(lock) { attached = null }
    }

    override fun onNotificationPosted(notification: NotificationPosted) {
        synchronized(lock) {
            attached?.let { return it.onNotificationPosted(notification) }
            evictExpired()
            buffer.addLast(BufferedPost(notification, elapsedRealtimeSource.elapsedRealtimeMillis()))
            while (buffer.size > MAX_BUFFERED) buffer.removeFirst()
        }
    }

    override fun onNotificationDismissed(dismiss: NotificationDismiss) {
        synchronized(lock) {
            attached?.let { return it.onNotificationDismissed(dismiss) }
            buffer.removeAll { it.notification.key == dismiss.key }
        }
    }

    override fun onIconData(icon: IconData) {
        synchronized(lock) { attached?.onIconData(icon) }
    }

    private fun evictExpired() {
        if (buffer.isEmpty()) return
        val now = elapsedRealtimeSource.elapsedRealtimeMillis()
        while (buffer.isNotEmpty() && now - buffer.first().bufferedAtMillis >= MAX_AGE_MILLIS) buffer.removeFirst()
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
