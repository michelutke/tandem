package dev.tandem.feature.files

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.text.format.Formatter
import androidx.core.app.NotificationCompat

/**
 * Ongoing notification for an in-flight transfer (E40-12): progress bar at the transfer's percent
 * and a Cancel action routed through [TransferActionReceiver]. Never shows the file name.
 */
class TransferProgressNotifier(
    private val context: Context,
) {
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    fun post(
        transferId: String,
        progress: TransferProgress,
    ) {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.files_progress_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(context.getString(R.string.files_progress_title))
                .setContentText(
                    context.getString(
                        R.string.files_progress_text,
                        progress.percent,
                        Formatter.formatShortFileSize(context, progress.bytesPerSecond),
                    ),
                ).setProgress(PERCENT_MAX, progress.percent, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .addAction(0, context.getString(R.string.files_progress_cancel), cancelIntent(transferId))
                .build()
        notificationManager.notify(transferId, NOTIFICATION_ID, notification)
    }

    fun cancel(transferId: String) {
        notificationManager.cancel(transferId, NOTIFICATION_ID)
    }

    private fun cancelIntent(transferId: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            (ACTION_CANCEL + transferId).hashCode(),
            Intent(ACTION_CANCEL)
                .putExtra(NotificationTransferPrompter.EXTRA_OFFER_ID, transferId)
                .setClass(context, TransferActionReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    internal companion object {
        const val CHANNEL_ID = "tandem_file_progress"
        const val NOTIFICATION_ID = 4008
        const val ACTION_CANCEL = "dev.tandem.feature.files.CANCEL_TRANSFER"
        private const val PERCENT_MAX = 100
    }
}
