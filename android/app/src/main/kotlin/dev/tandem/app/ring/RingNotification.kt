package dev.tandem.app.ring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import dev.tandem.app.R

/**
 * Ongoing "ring" notification with a "Stop" action (E23-06, F-4.4, UC-06): shown while the alarm
 * started by a received `Ring` is playing, so the user can dismiss it without opening the app.
 * Tapping "Stop" sends [RingStopActionReceiver.ACTION_STOP] as an explicit broadcast to this app's
 * own [RingStopActionReceiver] (never an implicit `Intent` another app could intercept, E00-28
 * invariants 1/4). Styled like [dev.tandem.app.service.TandemService]'s ongoing notification
 * (`Notification.Builder`, not `NotificationCompat`).
 */
object RingNotification {
    const val NOTIFICATION_ID = 2
    const val NOTIFICATION_CHANNEL_ID = "ring"

    /** Shows (or updates) the ongoing ring notification. */
    fun show(context: Context) {
        createNotificationChannel(context)
        context.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(context))
    }

    /** Cancels the ongoing ring notification (e.g. once the alarm has stopped). */
    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun createNotificationChannel(context: Context) {
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                context.getString(R.string.notification_ring_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            )
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(context: Context): Notification {
        val stopPendingIntent =
            PendingIntent.getBroadcast(
                context,
                STOP_REQUEST_CODE,
                Intent(context, RingStopActionReceiver::class.java).setAction(RingStopActionReceiver.ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE,
            )

        return Notification
            .Builder(context, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(context.getString(R.string.notification_ring_title))
            .setContentText(context.getString(R.string.notification_ring_text))
            .setSmallIcon(R.drawable.ic_notification_connection)
            .setOngoing(true)
            .addAction(
                Notification.Action
                    .Builder(null, context.getString(R.string.notification_ring_stop_action), stopPendingIntent)
                    .build(),
            ).build()
    }

    private const val STOP_REQUEST_CODE = 0
}
