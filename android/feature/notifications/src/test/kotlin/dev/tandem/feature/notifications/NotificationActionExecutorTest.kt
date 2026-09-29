package dev.tandem.feature.notifications

import android.app.Application
import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Process
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.NotificationActionResult
import dev.tandem.protocol.v1.notificationAction
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/**
 * `NotificationActionExecutor` E30-09 tests (`docs/planning/backlog/phase-3.yaml` E30-09's `tdd:`
 * list). Robolectric (E00-20): `Notification.Action`/`PendingIntent`/`StatusBarNotification` are
 * Android framework types; the shadowed `PendingIntent` records the fill-in `Intent` it was fired
 * with via Robolectric's broadcast-intent recording, the same convention this module's other
 * framework-touching tests use.
 */
@RunWith(AndroidJUnit4::class)
class NotificationActionExecutorTest {
    private val application: Application = RuntimeEnvironment.getApplication()
    private val context: Context = application

    @Test
    fun actionExecutor_plainActionIndexZero_sendsPendingIntentOfActionZero() {
        val pendingIntent = immutablePendingIntent(requestCode = 0)
        val sbn = statusBarNotification("key-1", plainAction(pendingIntent))
        val executor = NotificationActionExecutor(context) { key -> if (key == "key-1") sbn else null }

        executor.execute(
            notificationAction {
                key = "key-1"
                actionIndex = 0
            },
        )

        assertEquals(1, shadowOf(application).broadcastIntents.size)
    }

    @Test
    fun actionExecutor_replyText_fillInIntentCarriesRemoteInputResult() {
        val resultKey = "reply-result-key"
        val pendingIntent = mutableReplyPendingIntent(requestCode = 1)
        val sbn = statusBarNotification("key-2", replyAction(pendingIntent, resultKey))
        val executor = NotificationActionExecutor(context) { key -> if (key == "key-2") sbn else null }

        executor.execute(
            notificationAction {
                key = "key-2"
                actionIndex = 0
                replyText = "hello from mac"
            },
        )

        val fired = shadowOf(application).broadcastIntents.last()
        val results = RemoteInput.getResultsFromIntent(fired)
        assertEquals("hello from mac", results?.getCharSequence(resultKey)?.toString())
    }

    @Test
    fun actionExecutor_validAction_repliesResultOk() {
        val pendingIntent = immutablePendingIntent(requestCode = 2)
        val sbn = statusBarNotification("key-3", plainAction(pendingIntent))
        val executor = NotificationActionExecutor(context) { key -> if (key == "key-3") sbn else null }

        val result =
            executor.execute(
                notificationAction {
                    key = "key-3"
                    actionIndex = 0
                },
            )

        assertEquals(NotificationActionResult.Status.STATUS_OK, result.status)
        assertEquals("key-3", result.key)
    }

    @Test
    fun actionExecutor_unknownKey_repliesResultGoneWithoutThrowing() {
        val executor = NotificationActionExecutor(context) { null }

        val result =
            executor.execute(
                notificationAction {
                    key = "missing-key"
                    actionIndex = 0
                },
            )

        assertEquals(NotificationActionResult.Status.STATUS_GONE, result.status)
        assertEquals(0, shadowOf(application).broadcastIntents.size)
    }

    @Test
    fun actionExecutor_pendingIntentCanceled_repliesResultFailed() {
        val pendingIntent = immutablePendingIntent(requestCode = 3)
        pendingIntent.cancel()
        val sbn = statusBarNotification("key-4", plainAction(pendingIntent))
        val executor = NotificationActionExecutor(context) { key -> if (key == "key-4") sbn else null }

        val result =
            executor.execute(
                notificationAction {
                    key = "key-4"
                    actionIndex = 0
                },
            )

        assertEquals(NotificationActionResult.Status.STATUS_FAILED, result.status)
    }

    @Test
    fun actionExecutor_replyTextOverLimit_repliesResultFailedWithoutSending() {
        val pendingIntent = mutableReplyPendingIntent(requestCode = 4)
        val resultKey = "reply-result-key"
        val sbn = statusBarNotification("key-5", replyAction(pendingIntent, resultKey))
        val executor = NotificationActionExecutor(context) { key -> if (key == "key-5") sbn else null }

        val result =
            executor.execute(
                notificationAction {
                    key = "key-5"
                    actionIndex = 0
                    replyText = "a".repeat(4097)
                },
            )

        assertEquals(NotificationActionResult.Status.STATUS_FAILED, result.status)
        assertEquals(0, shadowOf(application).broadcastIntents.size)
    }

    @Test
    fun actionExecutor_unknownActionIndex_repliesResultGoneWithoutThrowing() {
        val pendingIntent = immutablePendingIntent(requestCode = 5)
        val sbn = statusBarNotification("key-6", plainAction(pendingIntent))
        val executor = NotificationActionExecutor(context) { key -> if (key == "key-6") sbn else null }

        val result =
            executor.execute(
                notificationAction {
                    key = "key-6"
                    actionIndex = 5
                },
            )

        assertEquals(NotificationActionResult.Status.STATUS_GONE, result.status)
    }

    private fun immutablePendingIntent(requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, NotificationActionExecutorTest::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

    // E00-28: RemoteInput direct-reply requires a mutable PendingIntent so the fill-in Intent's
    // RemoteInput results actually reach the fired Intent (tools/lint/pending-intent-mutable.allowlist).
    private fun mutableReplyPendingIntent(requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, NotificationActionExecutorTest::class.java),
            PendingIntent.FLAG_MUTABLE,
        )

    private fun plainAction(pendingIntent: PendingIntent): Notification.Action =
        Notification.Action
            .Builder(null as Icon?, "Ack", pendingIntent)
            .build()

    private fun replyAction(
        pendingIntent: PendingIntent,
        resultKey: String,
    ): Notification.Action {
        val remoteInput = RemoteInput.Builder(resultKey).setLabel("Reply").build()
        return Notification.Action
            .Builder(null as Icon?, "Reply", pendingIntent)
            .addRemoteInput(remoteInput)
            .build()
    }

    @Suppress("DEPRECATION")
    private fun statusBarNotification(
        key: String,
        vararg actions: Notification.Action,
    ): StatusBarNotification =
        StatusBarNotification(
            "com.example.chat",
            "com.example.chat",
            1,
            key,
            Process.myUid(),
            Process.myPid(),
            0,
            Notification
                .Builder(context, CHANNEL_ID)
                .also { builder -> actions.forEach { builder.addAction(it) } }
                .build(),
            Process.myUserHandle(),
            System.currentTimeMillis(),
        )

    private companion object {
        const val CHANNEL_ID = "test-channel"
    }
}
