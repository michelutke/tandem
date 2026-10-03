package dev.tandem.feature.messaging

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Receives the per-part sent/delivery PendingIntents built by [SmsManagerSender]; not exported. */
class SendResultReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val kind = SendResultKind.entries.firstOrNull { it.name == intent.getStringExtra(EXTRA_KIND) } ?: return
        val clientMessageId = intent.getStringExtra(EXTRA_CLIENT_MESSAGE_ID) ?: return
        val partIndex = intent.getIntExtra(EXTRA_PART_INDEX, -1)
        SendResultBus.publish(PartResult(clientMessageId, partIndex, kind, resultCode))
    }

    companion object {
        const val ACTION_RESULT = "dev.tandem.feature.messaging.SEND_RESULT"
        const val EXTRA_CLIENT_MESSAGE_ID = "clientMessageId"
        const val EXTRA_PART_INDEX = "partIndex"
        const val EXTRA_KIND = "kind"
    }
}
