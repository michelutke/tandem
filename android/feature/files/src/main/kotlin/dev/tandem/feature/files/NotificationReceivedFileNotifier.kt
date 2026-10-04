package dev.tandem.feature.files

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.net.toUri

/**
 * [ReceivedFileNotifier] posting one notification per received file (E40-13). Tapping it opens the
 * file with `ACTION_VIEW` on the MediaStore URI and a read grant. The name appears only in the
 * notification title, never in logs (invariant 7).
 */
class NotificationReceivedFileNotifier(
    private val context: Context,
) : ReceivedFileNotifier {
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    override fun notifyReceived(
        name: String,
        mime: String,
        contentUri: String,
    ) {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.files_received_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(context.getString(R.string.files_received_title, name))
                .setContentText(context.getString(R.string.files_received_text))
                .setContentIntent(viewIntent(mime, contentUri))
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .build()
        notificationManager.notify(contentUri, NOTIFICATION_ID, notification)
    }

    @Suppress("ImplicitInternalIntent", "PendingIntentImmutable") // ACTION_VIEW on a file is handled by another app.
    private fun viewIntent(
        mime: String,
        contentUri: String,
    ): PendingIntent =
        PendingIntent.getActivity(
            context,
            contentUri.hashCode(),
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(contentUri.toUri(), mime.ifEmpty { FALLBACK_MIME })
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    internal companion object {
        const val CHANNEL_ID = "tandem_file_received"
        const val NOTIFICATION_ID = 4008
        private const val FALLBACK_MIME = "application/octet-stream"
    }
}
