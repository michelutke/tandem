package dev.tandem.feature.notifications

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Process-lifetime [NotificationEventSink] (E30-16, SPEC.md F-5.1's disconnected-buffer policy):
 * while no session sink is attached, holds posted notifications in memory only, at most
 * [MAX_BUFFERED] entries (oldest dropped first) and each for at most [MAX_AGE_MILLIS], and hands
 * them oldest-first to the sink that [attach]es next. While attached, every event goes straight to
 * that sink. A dismiss for a still-buffered key removes it without telling anyone; other dismisses
 * and icons are dropped while detached. Expired entries are evicted on [detach] and by a timer on
 * [scope] (driven by [elapsedRealtimeSource]'s clock), so none outlives its age while the phone sits
 * disconnected; [clear] drops them all when the peer is unpaired.
 *
 * Invariant 7 (CLAUDE.md): never logs a [NotificationPosted] or any of its fields.
 */
class DisconnectedNotificationBuffer(
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val scope: CoroutineScope,
) : NotificationEventSink {
    private val lock = Any()
    private val buffer = ArrayDeque<BufferedPost>()
    private var attached: NotificationEventSink? = null
    private var evictionJob: Job? = null

    internal val size: Int get() = synchronized(lock) { buffer.size }

    fun attach(sink: NotificationEventSink) {
        synchronized(lock) {
            evictExpired()
            while (buffer.isNotEmpty()) sink.onNotificationPosted(buffer.removeFirst().notification)
            attached = sink
        }
    }

    fun detach() {
        synchronized(lock) {
            attached = null
            evictExpired()
        }
    }

    fun clear() {
        synchronized(lock) {
            buffer.clear()
            evictionJob?.cancel()
            evictionJob = null
        }
    }

    override fun onNotificationPosted(notification: NotificationPosted) {
        synchronized(lock) {
            attached?.let { return it.onNotificationPosted(notification) }
            evictExpired()
            buffer.addLast(BufferedPost(notification, elapsedRealtimeSource.elapsedRealtimeMillis()))
            while (buffer.size > MAX_BUFFERED) buffer.removeFirst()
            scheduleEviction()
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

    private fun scheduleEviction() {
        if (evictionJob != null) return
        evictionJob =
            scope.launch {
                while (true) {
                    val wait = synchronized(lock) { nextEvictionWaitMillis() } ?: return@launch
                    delay(wait)
                }
            }
    }

    private fun nextEvictionWaitMillis(): Long? {
        evictExpired()
        val oldest = buffer.firstOrNull()
        if (oldest == null) {
            evictionJob = null
            return null
        }
        return MAX_AGE_MILLIS - (elapsedRealtimeSource.elapsedRealtimeMillis() - oldest.bufferedAtMillis)
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
