package dev.tandem.feature.input

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

/** Posts the ongoing remote-input notification; [NOTIFICATION_ID] keeps it to a single entry. */
class AndroidNotificationPresenter(
    private val context: Context,
) : NotificationPresenter {
    private val manager = context.getSystemService(NotificationManager::class.java)

    override fun post(): Boolean {
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.remote_input_indicator_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        manager.notify(NOTIFICATION_ID, buildNotification())
        return true
    }

    override fun remove() = manager.cancel(NOTIFICATION_ID)

    override fun isPosted(): Boolean = manager.activeNotifications.any { it.id == NOTIFICATION_ID }

    private fun buildNotification(): Notification =
        Notification
            .Builder(context, CHANNEL_ID)
            .setContentTitle(context.getString(R.string.remote_input_indicator_title))
            .setContentText(context.getString(R.string.remote_input_indicator_text))
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .build()

    companion object {
        const val NOTIFICATION_ID = 62
        const val CHANNEL_ID = "remote_input_indicator"
    }
}
