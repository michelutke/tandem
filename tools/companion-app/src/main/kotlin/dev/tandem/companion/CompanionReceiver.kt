package dev.tandem.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * E00-22: posts a notification for every `kind` on `dev.tandem.companion.POST`, driven by
 * `adb shell am broadcast -a dev.tandem.companion.POST --es kind <kind> ...` or an instrumented
 * test's own explicit broadcast, so notification tests don't depend on a real third-party app.
 * Notification building lives in [CompanionNotifications].
 */
class CompanionReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        ensureChannel(context)
        val key = intent.getStringExtra(CompanionContract.EXTRA_KEY) ?: CompanionContract.DEFAULT_KEY

        when (intent.getStringExtra(CompanionContract.EXTRA_KIND)) {
            CompanionContract.KIND_PLAIN -> {
                post(context, key, CompanionNotifications.plain(context, intent))
            }

            CompanionContract.KIND_BIG_TEXT -> {
                post(context, key, CompanionNotifications.bigText(context, intent))
            }

            CompanionContract.KIND_MESSAGING_GROUP -> {
                post(context, key, CompanionNotifications.messagingGroup(context, intent))
            }

            CompanionContract.KIND_ACTIONS -> {
                post(context, key, CompanionNotifications.actions(context, key))
            }

            CompanionContract.KIND_SECRET -> {
                post(
                    context,
                    key,
                    CompanionNotifications.plain(context, intent).setVisibility(Notification.VISIBILITY_SECRET),
                )
            }

            CompanionContract.KIND_PRIVATE -> {
                post(
                    context,
                    key,
                    CompanionNotifications.plain(context, intent).setVisibility(Notification.VISIBILITY_PRIVATE),
                )
            }

            CompanionContract.KIND_ONGOING -> {
                post(context, key, CompanionNotifications.plain(context, intent).setOngoing(true))
            }

            CompanionContract.KIND_BURST -> {
                postBurst(context, intent, key)
            }

            CompanionContract.KIND_CANARY -> {
                post(context, key, CompanionNotifications.canary(context, intent))
            }

            CompanionContract.KIND_CANCEL -> {
                cancel(context, key)
            }
        }
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CompanionContract.CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CompanionContract.CHANNEL_ID, "Companion", NotificationManager.IMPORTANCE_HIGH),
            )
        }
    }

    private fun post(
        context: Context,
        key: String,
        builder: Notification.Builder,
    ) {
        context
            .getSystemService(NotificationManager::class.java)
            .notify(key, CompanionContract.NOTIFICATION_ID, builder.build())
    }

    private fun cancel(
        context: Context,
        key: String,
    ) {
        context.getSystemService(NotificationManager::class.java).cancel(key, CompanionContract.NOTIFICATION_ID)
    }

    // "burst (N updates in T ms on one key)": posts `count` updates to the same key, spread across
    // roughly `intervalMs` (T) total. Runs on a background thread (`goAsync()` keeps the receiver
    // alive past `onReceive` returning) so the ~1s spread never risks the broadcast ANR timeout.
    private fun postBurst(
        context: Context,
        intent: Intent,
        key: String,
    ) {
        val count = intent.getIntExtra(CompanionContract.EXTRA_COUNT, 1)
        val intervalMs = intent.getLongExtra(CompanionContract.EXTRA_INTERVAL_MS, 0L)
        val stepMs = if (count > 1) intervalMs / count else 0L
        val pendingResult = goAsync()
        Thread {
            try {
                for (update in 1..count) {
                    post(
                        context,
                        key,
                        Notification
                            .Builder(context, CompanionContract.CHANNEL_ID)
                            .setSmallIcon(android.R.drawable.stat_notify_chat)
                            .setContentTitle("Companion")
                            .setContentText("burst $update/$count"),
                    )
                    if (update < count && stepMs > 0) Thread.sleep(stepMs)
                }
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
