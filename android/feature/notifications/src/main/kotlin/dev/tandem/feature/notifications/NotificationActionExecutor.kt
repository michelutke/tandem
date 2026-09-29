package dev.tandem.feature.notifications

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.StatusBarNotification
import dev.tandem.protocol.v1.NotificationAction
import dev.tandem.protocol.v1.NotificationActionResult
import dev.tandem.protocol.v1.notificationActionResult

/**
 * E30-09: fires the `Notification.Action`/`PendingIntent` a received [NotificationAction] protocol
 * message refers to (by `key` + `action_index`), looked up via [notificationLookup] against the
 * still-tracked source [StatusBarNotification] -- [TandemNotificationListenerService] is the
 * production caller, keying it the same way [NotificationMapper] keys every NOTIFY message, off
 * `sbn.key`. Kept framework-decoupled from the listener service itself (only [Context],
 * [StatusBarNotification], and the platform notification/`RemoteInput` types) so it is
 * unit-testable under Robolectric (E00-20) with a fake [notificationLookup] and a real, shadowed
 * [PendingIntent].
 *
 * [execute] never throws: it always returns a [NotificationActionResult] so the caller can answer
 * the Mac unconditionally (E30-09 acceptance) -- `STATUS_GONE` for an unknown/expired key or an
 * `action_index` no longer in range (the source notification's actions already changed or the
 * notification itself is gone), `STATUS_FAILED` if the `PendingIntent` itself throws
 * [PendingIntent.CanceledException] or `reply_text` exceeds [MAX_REPLY_TEXT_LENGTH] characters
 * (rejected outright without ever sending the `PendingIntent`, never truncated -- the same
 * oversized-input convention `ClipboardTextKt` documents for the clipboard channel, E31-04),
 * `STATUS_OK` otherwise.
 *
 * The fill-in `Intent` sent to the `PendingIntent` carries only the `RemoteInput` results for the
 * action's own result keys -- nothing else from [NotificationAction] ever reaches it.
 */
class NotificationActionExecutor(
    private val context: Context,
    private val notificationLookup: (key: String) -> StatusBarNotification?,
) {
    fun execute(action: NotificationAction): NotificationActionResult =
        notificationActionResult {
            key = action.key
            status = fire(action)
        }

    private fun fire(action: NotificationAction): NotificationActionResult.Status {
        val sourceAction = notificationLookup(action.key)?.notification?.actions?.getOrNull(action.actionIndex)
        return when {
            sourceAction == null -> NotificationActionResult.Status.STATUS_GONE
            action.replyText.length > MAX_REPLY_TEXT_LENGTH -> NotificationActionResult.Status.STATUS_FAILED
            else -> send(sourceAction, action.replyText)
        }
    }

    private fun send(
        sourceAction: Notification.Action,
        replyText: String,
    ): NotificationActionResult.Status {
        val fillInIntent = Intent()
        if (replyText.isNotEmpty()) addReplyResult(fillInIntent, sourceAction, replyText)
        return try {
            sourceAction.actionIntent.send(context, 0, fillInIntent)
            NotificationActionResult.Status.STATUS_OK
        } catch (_: PendingIntent.CanceledException) {
            NotificationActionResult.Status.STATUS_FAILED
        }
    }

    private fun addReplyResult(
        fillInIntent: Intent,
        sourceAction: Notification.Action,
        replyText: String,
    ) {
        val remoteInputs = sourceAction.remoteInputs ?: return
        if (remoteInputs.isEmpty()) return
        val results = Bundle()
        for (remoteInput in remoteInputs) {
            results.putCharSequence(remoteInput.resultKey, replyText)
        }
        RemoteInput.addResultsToIntent(remoteInputs, fillInIntent, results)
    }

    private companion object {
        const val MAX_REPLY_TEXT_LENGTH = 4096
    }
}
