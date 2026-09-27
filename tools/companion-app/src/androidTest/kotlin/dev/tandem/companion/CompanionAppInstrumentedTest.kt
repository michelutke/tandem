package dev.tandem.companion

import android.app.Notification
import android.app.NotificationManager
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * E00-22 tdd: `companionApp_*` — the companion app's own kind coverage, driven the same way a
 * real caller drives it (`adb shell am broadcast`), just via `Context.sendBroadcast` instead.
 */
@RunWith(AndroidJUnit4::class)
class CompanionAppInstrumentedTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    @Before
    fun grantNotificationPermission() {
        InstrumentationRegistry
            .getInstrumentation()
            .uiAutomation
            .executeShellCommand("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS")
            .close()
    }

    @Test
    fun companionApp_postMessagingGroupThreeSenders_notificationHasThreeMessages() {
        val key = "messaging-group-test"
        postCommand(key, CompanionContract.KIND_MESSAGING_GROUP) {
            putExtra(CompanionContract.EXTRA_SENDERS, 3)
        }

        val notification = awaitActiveNotification(key)
        // Notification.MessagingStyle.Message.getMessagesFromBundleArray(...) is API 30+ only
        // (this module's minSdk is 29, and CI runs an API 29 device); reading the raw extras
        // array's size checks the same thing without needing that method.
        val messages = requireNotNull(notification.extras.getParcelableArray(Notification.EXTRA_MESSAGES))
        assertEquals(3, messages.size)
    }

    @Test
    fun companionApp_remoteInputReplyReceived_replyTextReadableViaProvider() {
        val key = "reply-test"
        val replyText = "on my way"

        val remoteInput = RemoteInput.Builder(CompanionContract.REMOTE_INPUT_KEY).build()
        val resultIntent =
            Intent(CompanionContract.ACTION_FIRED)
                .setPackage(context.packageName)
                .putExtra(CompanionContract.EXTRA_KEY, key)
                .putExtra(CompanionContract.EXTRA_ACTION_ID, CompanionContract.ACTION_ID_REPLY)
        val results = Bundle().apply { putCharSequence(CompanionContract.REMOTE_INPUT_KEY, replyText) }
        RemoteInput.addResultsToIntent(arrayOf(remoteInput), resultIntent, results)
        context.sendBroadcast(resultIntent)

        val deadline = System.nanoTime() + REPLY_TIMEOUT_NANOS
        var readBack: String? = null
        while (System.nanoTime() < deadline && readBack == null) {
            readBack = queryReplyText(key)
            if (readBack == null) Thread.sleep(POLL_INTERVAL_MS)
        }
        assertEquals(replyText, readBack)
    }

    @Test
    fun companionApp_burst50In1000ms_postsExactly50Updates() {
        val key = "burst-test"
        postCommand(key, CompanionContract.KIND_BURST) {
            putExtra(CompanionContract.EXTRA_COUNT, BURST_COUNT)
            putExtra(CompanionContract.EXTRA_INTERVAL_MS, BURST_WINDOW_MS)
        }

        val notification = awaitBurstComplete(key)
        assertEquals(
            "burst $BURST_COUNT/$BURST_COUNT",
            notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString(),
        )
    }

    @Test
    fun companionApp_canaryKind_notificationTextContainsNonce() {
        val key = "canary-test"
        val nonce = "abc123"
        postCommand(key, CompanionContract.KIND_CANARY) {
            putExtra(CompanionContract.EXTRA_NONCE, nonce)
        }

        val notification = awaitActiveNotification(key)
        val text = notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
        assertTrue(text.contains("TANDEM-CANARY-$nonce"))
    }

    private fun postCommand(
        key: String,
        kind: String,
        extras: Intent.() -> Unit = {},
    ) {
        val intent =
            Intent(CompanionContract.ACTION_POST)
                .setPackage(context.packageName)
                .putExtra(CompanionContract.EXTRA_KIND, kind)
                .putExtra(CompanionContract.EXTRA_KEY, key)
        intent.extras()
        context.sendBroadcast(intent)
    }

    private fun awaitActiveNotification(key: String): Notification {
        val deadline = System.nanoTime() + REPLY_TIMEOUT_NANOS
        while (System.nanoTime() < deadline) {
            val match = notificationManager.activeNotifications.firstOrNull { it.tag == key }
            if (match != null) return match.notification
            Thread.sleep(POLL_INTERVAL_MS)
        }
        error("no active notification for key=$key within timeout")
    }

    // The companion app paces burst updates to stay under the platform's notification-update
    // shedding threshold (see CompanionReceiver.MIN_STEP_MS), so a full 50-update burst can take
    // several seconds longer than the requested intervalMs; poll for the final "N/N" text instead
    // of guessing a fixed sleep.
    private fun awaitBurstComplete(key: String): Notification {
        val deadline = System.nanoTime() + BURST_TIMEOUT_NANOS
        val expectedText = "burst $BURST_COUNT/$BURST_COUNT"
        var last: Notification? = null
        while (System.nanoTime() < deadline) {
            val match = notificationManager.activeNotifications.firstOrNull { it.tag == key }
            if (match != null) {
                last = match.notification
                if (last.extras.getCharSequence(Notification.EXTRA_TEXT).toString() == expectedText) return last
            }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        return last ?: error("no active notification for key=$key within timeout")
    }

    private fun queryReplyText(key: String): String? {
        val uri =
            android.net.Uri
                .Builder()
                .scheme("content")
                .authority(CompanionContract.AUTHORITY)
                .appendPath(CompanionContract.PATH_REPLIES)
                .build()
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val keyColumn = cursor.getColumnIndexOrThrow(CompanionContract.COLUMN_KEY)
            val textColumn = cursor.getColumnIndexOrThrow(CompanionContract.COLUMN_TEXT)
            while (cursor.moveToNext()) {
                if (cursor.getString(keyColumn) == key) return cursor.getString(textColumn)
            }
        }
        return null
    }

    private companion object {
        const val POLL_INTERVAL_MS = 50L
        val REPLY_TIMEOUT_NANOS =
            java.util.concurrent.TimeUnit.SECONDS
                .toNanos(8)
        const val BURST_COUNT = 50
        const val BURST_WINDOW_MS = 1000L
        val BURST_TIMEOUT_NANOS =
            java.util.concurrent.TimeUnit.SECONDS
                .toNanos(30)
    }
}
