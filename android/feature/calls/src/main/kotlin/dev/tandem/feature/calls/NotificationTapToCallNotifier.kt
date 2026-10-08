package dev.tandem.feature.calls

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Production [TapToCallNotifier] (E52-05): a high-priority notification whose tap starts
 * [TapToCallActivity], which places the call with `ACTION_CALL` (CALL_PHONE). The number is only
 * in the private notification body; the lock-screen version carries none.
 */
class NotificationTapToCallNotifier(
    private val context: Context,
) : TapToCallNotifier {
    override fun post(
        address: String,
        subscriptionId: Int,
    ) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.calls_tap_to_call_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val publicVersion =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle(context.getString(R.string.calls_tap_to_call_title))
                .setContentText(context.getString(R.string.calls_tap_to_call_public_text))
                .build()
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle(context.getString(R.string.calls_tap_to_call_title))
                .setContentText(context.getString(R.string.calls_tap_to_call_text, address))
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setAutoCancel(true)
                .setContentIntent(callIntent(address, subscriptionId))
                .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun callIntent(
        address: String,
        subscriptionId: Int,
    ): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, TapToCallActivity::class.java)
                .putExtra(TapToCallActivity.EXTRA_ADDRESS, address)
                .putExtra(TapToCallActivity.EXTRA_SUBSCRIPTION_ID, subscriptionId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private companion object {
        const val CHANNEL_ID = "tap-to-call"
        const val NOTIFICATION_ID = 0x7A11
    }
}
