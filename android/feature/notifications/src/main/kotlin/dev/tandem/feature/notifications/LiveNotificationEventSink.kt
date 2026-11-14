package dev.tandem.feature.notifications

import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
import dev.tandem.feature.notifications.di.NotificationDispatchers
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob

/**
 * The [NotificationEventSink] [TandemNotificationListenerService] forwards to by default (E20-23).
 * The system constructs the listener, so the connection orchestrator's notifications feature
 * [attach]es the session-backed sink while a session is attached and [detach]es it when it closes;
 * in between, posts wait in a process-lifetime [DisconnectedNotificationBuffer] (E30-16).
 */
object LiveNotificationEventSink : NotificationEventSink {
    private val buffer =
        DisconnectedNotificationBuffer(
            SystemElapsedRealtimeSource,
            CoroutineScope(SupervisorJob() + NotificationDispatchers.default),
        )

    fun attach(sink: NotificationEventSink) = buffer.attach(sink)

    fun detach() = buffer.detach()

    /** Drops every buffered post, as for an unpair. */
    fun clear() = buffer.clear()

    override fun onNotificationPosted(notification: NotificationPosted) = buffer.onNotificationPosted(notification)

    override fun onNotificationDismissed(dismiss: NotificationDismiss) = buffer.onNotificationDismissed(dismiss)

    override fun onIconData(icon: IconData) = buffer.onIconData(icon)
}
