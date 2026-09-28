package dev.tandem.feature.notifications

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.NotificationDismiss
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Reads [session]'s NOTIFY channel until it finishes (peer disconnect or app teardown), calling
 * [cancelNotification] with the `key` of every macos-origin `NotificationDismiss` frame it sees;
 * every other NOTIFY payload is ignored here (`NotificationPosted`/`NotificationActionResult`
 * handling is E30-16/E30-08). Mirrors macOS's `startNotificationPresentationReader`
 * (FeatureNotifications) as a free function so a composition root can launch one per session
 * without this module depending on wherever that root lives; wiring [cancelNotification] to
 * `TandemNotificationListenerService.notificationCanceller` is that composition root's job (E30-10
 * out of scope, same as the macOS twin).
 */
fun startNotificationDismissReader(
    scope: CoroutineScope,
    session: TandemSession,
    cancelNotification: (key: String) -> Unit,
): Job =
    scope.launch {
        session.receive(Channel.CHANNEL_NOTIFY).collect { frame ->
            if (frame.payloadCase != Envelope.PayloadCase.NOTIFICATION_DISMISS) return@collect
            val dismiss = frame.notificationDismiss
            if (dismiss.origin == NotificationDismiss.Origin.ORIGIN_MACOS) {
                cancelNotification(dismiss.key)
            }
        }
    }
