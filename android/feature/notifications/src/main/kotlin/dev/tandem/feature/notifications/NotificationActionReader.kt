package dev.tandem.feature.notifications

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Reads [session]'s NOTIFY channel until it finishes (peer disconnect or app teardown), firing
 * every received `NotificationAction` through [executor] and sending the resulting
 * `NotificationActionResult` straight back on the same channel (E30-09 acceptance: "every received
 * NotificationAction is answered"). Mirrors `startNotificationDismissReader` (E30-10) as a free
 * function so a composition root can launch one per session without this module depending on
 * wherever that root lives; wiring [executor]'s `notificationLookup` to
 * `TandemNotificationListenerService.findTrackedNotification` is that composition root's job, same
 * as E30-10's `notificationCanceller` wiring.
 */
fun startNotificationActionReader(
    scope: CoroutineScope,
    session: TandemSession,
    executor: NotificationActionExecutor,
): Job =
    scope.launch {
        session.receive(Channel.CHANNEL_NOTIFY).collect { frame ->
            if (frame.payloadCase != Envelope.PayloadCase.NOTIFICATION_ACTION) return@collect
            val result = executor.execute(frame.notificationAction)
            session.send(Channel.CHANNEL_NOTIFY) { notificationActionResult = result }
        }
    }
