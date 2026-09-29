package dev.tandem.feature.notifications

import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import kotlinx.coroutines.CoroutineDispatcher
import java.time.Clock
import java.time.Duration

/**
 * E30-12: wraps [downstream] with an [UpdateCoalescer] keyed by [NotificationPosted.key], so a
 * key updating faster than [window] forwards to [downstream] at most once per [window] instead of
 * once per post. Dismissals always pass straight through: they are not rate-limited, and a
 * dismiss also drops [key]'s coalescer state so any value already pending for it is never
 * forwarded after the notification is gone.
 */
class CoalescingNotificationEventSink(
    private val downstream: NotificationEventSink,
    clock: Clock,
    dispatcher: CoroutineDispatcher,
    window: Duration = Duration.ofMillis(DEFAULT_WINDOW_MILLIS),
) : NotificationEventSink {
    private val coalescer =
        UpdateCoalescer<String, NotificationPosted>(
            forward = downstream::onNotificationPosted,
            clock = clock,
            dispatcher = dispatcher,
            window = window,
        )

    /** Stops all pending coalesced sends and cancels this instance's scope. */
    fun close() {
        coalescer.close()
    }

    override fun onNotificationPosted(notification: NotificationPosted) {
        coalescer.update(notification.key, notification)
    }

    override fun onNotificationDismissed(dismiss: NotificationDismiss) {
        coalescer.remove(dismiss.key)
        downstream.onNotificationDismissed(dismiss)
    }

    private companion object {
        const val DEFAULT_WINDOW_MILLIS = 500L
    }
}
