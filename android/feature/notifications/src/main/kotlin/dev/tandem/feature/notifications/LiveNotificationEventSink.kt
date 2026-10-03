package dev.tandem.feature.notifications

import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted

/**
 * The [NotificationEventSink] [TandemNotificationListenerService] forwards to by default (E20-23).
 * The system constructs the listener, so the connection orchestrator's notifications feature
 * points [target] at the session-backed sink while a session is attached and back at
 * [NotificationEventSink.NoOp] when it closes.
 */
object LiveNotificationEventSink : NotificationEventSink {
    @Volatile
    var target: NotificationEventSink = NotificationEventSink.NoOp

    override fun onNotificationPosted(notification: NotificationPosted) = target.onNotificationPosted(notification)

    override fun onNotificationDismissed(dismiss: NotificationDismiss) = target.onNotificationDismissed(dismiss)

    override fun onIconData(icon: IconData) = target.onIconData(icon)
}
