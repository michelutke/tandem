package dev.tandem.feature.notifications

import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted

/**
 * The [NotificationEventSink] [TandemNotificationListenerService] forwards to by default (E20-23).
 * The system constructs the listener, so the connection orchestrator's notifications feature
 * [attach]es the session-backed sink while a session is attached and [detach]es it when it closes;
 * in between, posts wait in a process-lifetime [DisconnectedNotificationBuffer] (E30-16).
 */
object LiveNotificationEventSink : NotificationEventSink {
    private val buffer = DisconnectedNotificationBuffer(SystemElapsedRealtimeSource)

    fun attach(sink: NotificationEventSink) = buffer.attach(sink)

    fun detach() = buffer.detach()

    override fun onNotificationPosted(notification: NotificationPosted) = buffer.onNotificationPosted(notification)

    override fun onNotificationDismissed(dismiss: NotificationDismiss) = buffer.onNotificationDismissed(dismiss)

    override fun onIconData(icon: IconData) = buffer.onIconData(icon)
}
