package dev.tandem.feature.files

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import dev.tandem.protocol.v1.PhotoAccess

/**
 * Posts the "Select more photos" notification when the Mac asks for more than a PARTIAL grant
 * exposes; the fixed [NOTIFICATION_ID] keeps repeated requests to a single notification.
 */
class SelectMorePhotosNotifier(
    private val context: Context,
    private val permissionChecker: MediaPermissionChecker,
) {
    fun onMoreRequested() {
        if (permissionChecker.access() != PhotoAccess.PHOTO_ACCESS_PARTIAL) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.select_more_photos_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification =
        Notification
            .Builder(context, CHANNEL_ID)
            .setContentTitle(context.getString(R.string.select_more_photos_title))
            .setContentText(context.getString(R.string.select_more_photos_text))
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setAutoCancel(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(context, MediaPermissionRequestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_IMMUTABLE,
                ),
            ).build()

    companion object {
        const val NOTIFICATION_ID = 41
        const val CHANNEL_ID = "select_more_photos"
    }
}
