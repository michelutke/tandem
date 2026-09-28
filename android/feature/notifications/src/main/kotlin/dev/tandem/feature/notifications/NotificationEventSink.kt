package dev.tandem.feature.notifications

import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted

/**
 * Minimal callback seam [TandemNotificationListenerService] emits mapped notification events to.
 * The session-facing sink with disconnected buffering (bounded, drop-oldest, flush on reconnect)
 * is E30-16; this interface is deliberately just enough for E30-02's listener/mapper to be
 * testable without it, and is expected to grow a real implementation there.
 */
interface NotificationEventSink {
    fun onNotificationPosted(notification: NotificationPosted)

    fun onNotificationDismissed(dismiss: NotificationDismiss)

    companion object {
        val NoOp: NotificationEventSink =
            object : NotificationEventSink {
                override fun onNotificationPosted(notification: NotificationPosted) = Unit

                override fun onNotificationDismissed(dismiss: NotificationDismiss) = Unit
            }
    }
}
