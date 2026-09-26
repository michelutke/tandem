package dev.tandem.companion

import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * E00-22: target of every `actions` kind's `PendingIntent` (button tap and RemoteInput reply).
 * Records the fired action, and the reply text if the action carried a RemoteInput result, so
 * instrumented tests can read them back through [RecordsProvider].
 */
class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val key = intent.getStringExtra(CompanionContract.EXTRA_KEY) ?: return
        val actionId = intent.getStringExtra(CompanionContract.EXTRA_ACTION_ID) ?: return
        CompanionRecords.actionsFired += CompanionRecords.ActionFired(key, actionId)

        val replyText =
            RemoteInput
                .getResultsFromIntent(intent)
                ?.getCharSequence(CompanionContract.REMOTE_INPUT_KEY)
                ?.toString()
        if (replyText != null) {
            CompanionRecords.repliesReceived += CompanionRecords.ReplyReceived(key, replyText)
        }
    }
}
