package dev.tandem.feature.files

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.text.format.Formatter
import androidx.core.app.NotificationCompat

/**
 * [TransferPrompter] posting a heads-up notification with exactly two actions, Accept and Decline
 * (E40-07), routed through [TransferActionReceiver]. Shows only the already-sanitized name and size.
 * With [contentActivity], tapping the notification opens that in-app surface (explicit component,
 * extras [EXTRA_OFFER_ID], [EXTRA_DISPLAY_NAME] and [EXTRA_SIZE_BYTES]).
 */
class NotificationTransferPrompter(
    private val context: Context,
    private val contentActivity: Class<out Activity>? = null,
) : TransferPrompter {
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    override fun post(
        offerId: String,
        displayName: String,
        sizeBytes: Long,
    ) {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.files_offer_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val builder =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(context.getString(R.string.files_offer_title))
                .setContentText(
                    context.getString(
                        R.string.files_offer_text,
                        displayName,
                        Formatter.formatShortFileSize(context, sizeBytes),
                    ),
                ).setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setOnlyAlertOnce(true)
                .addAction(0, context.getString(R.string.files_offer_accept), actionIntent(ACTION_ACCEPT, offerId))
                .addAction(0, context.getString(R.string.files_offer_decline), actionIntent(ACTION_DECLINE, offerId))
        contentActivity?.let { builder.setContentIntent(contentIntent(it, offerId, displayName, sizeBytes)) }
        notificationManager.notify(offerId, NOTIFICATION_ID, builder.build())
    }

    override fun cancel(offerId: String) {
        notificationManager.cancel(offerId, NOTIFICATION_ID)
    }

    private fun contentIntent(
        activity: Class<out Activity>,
        offerId: String,
        displayName: String,
        sizeBytes: Long,
    ): PendingIntent =
        PendingIntent.getActivity(
            context,
            (ACTION_ACCEPT + offerId).hashCode(),
            Intent()
                .setClass(context, activity)
                .putExtra(EXTRA_OFFER_ID, offerId)
                .putExtra(EXTRA_DISPLAY_NAME, displayName)
                .putExtra(EXTRA_SIZE_BYTES, sizeBytes),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun actionIntent(
        action: String,
        offerId: String,
    ): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            (action + offerId).hashCode(),
            Intent(action).putExtra(EXTRA_OFFER_ID, offerId).setClass(context, TransferActionReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    companion object {
        const val CHANNEL_ID = "tandem_file_offers"
        const val NOTIFICATION_ID = 4007
        const val ACTION_ACCEPT = "dev.tandem.feature.files.ACCEPT_OFFER"
        const val ACTION_DECLINE = "dev.tandem.feature.files.DECLINE_OFFER"
        const val EXTRA_OFFER_ID = "offerId"
        const val EXTRA_DISPLAY_NAME = "displayName"
        const val EXTRA_SIZE_BYTES = "sizeBytes"
    }
}
