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
    // roughly `intervalMs` (T) total, but never faster than MIN_STEP_MS apart. Runs on a
    // background thread (`goAsync()` keeps the receiver alive past `onReceive` returning) since
    // pacing a real burst can run well past the broadcast ANR timeout.
    //
    // NotificationManagerService sheds (silently drops, not delays) notification *updates* to the
    // same id/tag above ~10/sec per package (Android N+); requesting a faster pace than that would
    // make some updates never land no matter how long a caller waits, so MIN_STEP_MS floors the
    // pace at the platform-recommended safe rate instead of honoring an unsafe `intervalMs`. Even
    // at that paced rate, a loaded CI emulator can still shed an occasional update (observed:
    // several updates missing from a 50-update burst under concurrent CI load) -- so each update is
    // read back via [activeNotificationText] and re-`notify()`'d (with backoff) until it is
    // confirmed to have actually landed, rather than assuming a single `notify()` call is enough.
    private fun postBurst(
        context: Context,
        intent: Intent,
        key: String,
    ) {
        val count = intent.getIntExtra(CompanionContract.EXTRA_COUNT, 1)
        val intervalMs = intent.getLongExtra(CompanionContract.EXTRA_INTERVAL_MS, 0L)
        val requestedStepMs = if (count > 1) intervalMs / count else 0L
        val stepMs = maxOf(requestedStepMs, MIN_STEP_MS)
        val pendingResult = goAsync()
        Thread {
            try {
                for (update in 1..count) {
                    postBurstStepUntilConfirmed(context, key, update, count)
                    if (update < count && stepMs > 0) Thread.sleep(stepMs)
                }
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun postBurstStepUntilConfirmed(
        context: Context,
        key: String,
        update: Int,
        count: Int,
    ) {
        val expectedText = "burst $update/$count"
        repeat(BURST_STEP_MAX_ATTEMPTS) {
            post(
                context,
                key,
                Notification
                    .Builder(context, CompanionContract.CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.stat_notify_chat)
                    .setContentTitle("Companion")
                    .setContentText(expectedText),
            )
            if (awaitLanded(context, key, expectedText)) return
        }
    }

    // Re-posting faster than the shedding threshold would itself get shed, so wait up to
    // BURST_STEP_CONFIRM_WINDOW_MS for an update to land before re-posting it.
    private fun awaitLanded(
        context: Context,
        key: String,
        expectedText: String,
    ): Boolean {
        repeat((BURST_STEP_CONFIRM_WINDOW_MS / BURST_STEP_CONFIRM_POLL_MS).toInt()) {
            Thread.sleep(BURST_STEP_CONFIRM_POLL_MS)
            if (activeNotificationText(context, key) == expectedText) return true
        }
        return false
    }

    private fun activeNotificationText(
        context: Context,
        key: String,
    ): String? =
        context
            .getSystemService(NotificationManager::class.java)
            .activeNotifications
            .firstOrNull { it.tag == key }
            ?.notification
            ?.extras
            ?.getCharSequence(Notification.EXTRA_TEXT)
            ?.toString()

    private companion object {
        // NotificationManagerService's ~10/sec shedding threshold (Android N+) is measured with
        // enough slack/jitter that even a steady 5/sec (200ms) pace occasionally sheds one or two
        // updates on a loaded emulator; ~3/sec leaves real margin.
        const val MIN_STEP_MS = 500L

        // How often to read the notification back after a notify() call, how long to wait for it
        // to land before re-posting, and how many times to retry a step before giving up (the awaiting test itself
        // has a much longer overall timeout and will report the true final count either way).
        const val BURST_STEP_CONFIRM_POLL_MS = 100L
        const val BURST_STEP_CONFIRM_WINDOW_MS = 1_000L
        const val BURST_STEP_MAX_ATTEMPTS = 5
    }
}
