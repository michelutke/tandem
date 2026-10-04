package dev.tandem.feature.mirror

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * [MirrorPromptPresenter] posting one heads-up notification "Mirror to <Mac>?" (E61-16) with Start
 * and Not now actions, routed through [MirrorPromptActionReceiver]. Swiping it away is a decline.
 */
class NotificationMirrorPromptPresenter(
    private val context: Context,
) : MirrorPromptPresenter {
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    override fun show(peerName: String) {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.mirror_prompt_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val start = actionIntent(ACTION_START)
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setContentTitle(context.getString(R.string.mirror_prompt_title, peerName))
                .setContentText(context.getString(R.string.mirror_prompt_text, peerName))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOnlyAlertOnce(true)
                .setContentIntent(start)
                .setDeleteIntent(actionIntent(ACTION_DECLINE))
                .addAction(0, context.getString(R.string.mirror_prompt_start), start)
                .addAction(0, context.getString(R.string.mirror_prompt_decline), actionIntent(ACTION_DECLINE))
                .build()
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun remove() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun actionIntent(action: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            action.hashCode(),
            Intent(action).setClass(context, MirrorPromptActionReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    internal companion object {
        const val CHANNEL_ID = "tandem_mirror_requests"
        const val NOTIFICATION_ID = 4061
        const val ACTION_START = "dev.tandem.feature.mirror.START_MIRROR"
        const val ACTION_DECLINE = "dev.tandem.feature.mirror.DECLINE_MIRROR"
    }
}
