package dev.tandem.feature.notifications

import android.app.Notification
import android.app.Person
import android.content.Context
import android.os.Process
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.NotificationDismiss
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// E30-02 tdd:
//   unit: notificationMapper_plainStatusBarNotification_mapsPackageVersionTitleText
//   unit: notificationMapper_messagingStyleThreeSenders_preservesSenderNamesInOrder
//   unit: notificationMapper_removedCallback_emitsDismissWithOriginAndroid
//
// Runs on Robolectric (E00-20): StatusBarNotification/Notification are Android framework types
// NotificationMapper itself has no other Android dependency (framework-decoupled per the issue).
// No notification channel is registered: Notification.Builder(context, channelId).build() does
// not require a pre-existing channel, and these tests never call NotificationManager.notify().
@RunWith(AndroidJUnit4::class)
class NotificationMapperTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun notificationMapper_plainStatusBarNotification_mapsPackageVersionTitleText() {
        val notification =
            Notification
                .Builder(context, CHANNEL_ID)
                .setContentTitle("Alice")
                .setContentText("On my way")
                .build()
        val sbn = statusBarNotification(packageName = "com.example.chat", notification = notification)

        val posted = NotificationMapper.toPosted(sbn, appVersionCode = 42L)

        assertEquals("com.example.chat", posted.packageName)
        assertEquals(42L, posted.appVersionCode)
        assertEquals("Alice", posted.title)
        assertEquals("On my way", posted.text)
    }

    @Test
    fun notificationMapper_messagingStyleThreeSenders_preservesSenderNamesInOrder() {
        val me = Person.Builder().setName("Me").build()
        val style = Notification.MessagingStyle(me)
        listOf("Alice", "Bob", "Carol").forEachIndexed { index, senderName ->
            style.addMessage("message $index", index.toLong(), Person.Builder().setName(senderName).build())
        }
        val notification = Notification.Builder(context, CHANNEL_ID).setStyle(style).build()
        val sbn = statusBarNotification(packageName = "com.example.chat", notification = notification)

        val posted = NotificationMapper.toPosted(sbn, appVersionCode = 1L)

        assertEquals(listOf("Alice", "Bob", "Carol"), posted.messagingStyleSendersList)
    }

    @Test
    fun notificationMapper_removedCallback_emitsDismissWithOriginAndroid() {
        val notification = Notification.Builder(context, CHANNEL_ID).build()
        val sbn = statusBarNotification(packageName = "com.example.chat", notification = notification)

        val dismiss = NotificationMapper.toDismiss(sbn)

        assertEquals(sbn.key, dismiss.key)
        assertEquals(NotificationDismiss.Origin.ORIGIN_ANDROID, dismiss.origin)
    }

    // The `tag` argument feeds StatusBarNotification's internally computed `key` (pkg/id/tag/uid),
    // not the key itself -- assertions above read `sbn.key` back rather than hardcoding it. The
    // 10-arg constructor is the only non-Parcel public constructor available (deprecated since
    // apps normally never construct one themselves; only the system does).
    @Suppress("DEPRECATION")
    private fun statusBarNotification(
        packageName: String,
        notification: Notification,
    ): StatusBarNotification =
        StatusBarNotification(
            packageName,
            packageName,
            1,
            "tag",
            Process.myUid(),
            Process.myPid(),
            0,
            notification,
            Process.myUserHandle(),
            System.currentTimeMillis(),
        )

    private companion object {
        const val CHANNEL_ID = "test-channel"
    }
}
