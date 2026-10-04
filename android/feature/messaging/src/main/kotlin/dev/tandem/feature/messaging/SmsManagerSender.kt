package dev.tandem.feature.messaging

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.telephony.SmsManager

/** [SmsSender] over `SmsManager.sendMultipartTextMessage` with one sent and one delivery PendingIntent per part. */
class SmsManagerSender(
    private val context: Context,
) : SmsSender {
    override fun divide(body: String): List<String> = smsManager(subscriptionId = 0).divideMessage(body)

    override fun send(message: OutgoingSms) {
        val sentIntents = message.parts.indices.map { pendingIntent(message, it, SendResultKind.SENT) }
        val deliveryIntents = message.parts.indices.map { pendingIntent(message, it, SendResultKind.DELIVERED) }
        smsManager(message.subscriptionId).sendMultipartTextMessage(
            message.destination,
            null,
            ArrayList(message.parts),
            ArrayList(sentIntents),
            ArrayList(deliveryIntents),
        )
    }

    // createForSubscriptionId needs API 31; minSdk is 29.
    @Suppress("DEPRECATION")
    private fun smsManager(subscriptionId: Int): SmsManager =
        if (subscriptionId > 0) {
            SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        } else {
            context.getSystemService(SmsManager::class.java)
        }

    private fun pendingIntent(
        message: OutgoingSms,
        partIndex: Int,
        kind: SendResultKind,
    ): PendingIntent {
        val id = Uri.encode(message.clientMessageId)
        return PendingIntent.getBroadcast(
            context,
            0,
            Intent()
                .setAction(SendResultReceiver.ACTION_RESULT)
                .setData(Uri.parse("tandem-sms://send/$id/$partIndex/${kind.name}"))
                .putExtra(SendResultReceiver.EXTRA_CLIENT_MESSAGE_ID, message.clientMessageId)
                .putExtra(SendResultReceiver.EXTRA_PART_INDEX, partIndex)
                .putExtra(SendResultReceiver.EXTRA_KIND, kind.name)
                .setClass(context, SendResultReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

class ContextSendSmsPermission(
    private val context: Context,
) : SendSmsPermission {
    override fun isGranted(): Boolean =
        context.checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
}
