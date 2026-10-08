package dev.tandem.feature.notifications

import android.app.Notification
import android.content.Context
import android.os.Process
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// E30-03 tdd:
//   unit: defaultFilter_ownPackage_dropped
//   unit: defaultFilter_packageComAndroidSystemui_dropped
//   unit: defaultFilter_packageAndroid_dropped
//   unit: defaultFilter_ordinaryAppPlainPost_forwarded
//   unit: defaultFilter_foregroundServiceFlag_dropped
//   unit: defaultFilter_groupSummaryWithTwoChildren_summaryDroppedChildrenForwarded
//   unit: defaultFilter_mediaStyleTemplate_dropped
//
// Rule set is documented in SYSTEM_NOISE.md and referenced from SPEC.md's NOTIFY section.
@RunWith(AndroidJUnit4::class)
class NotificationFilterTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun defaultFilter_ownPackage_dropped() {
        val sbn = statusBarNotification(packageName = OWN_PACKAGE, notification = plainNotification())

        assertFalse(NotificationFilter.shouldForward(sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun defaultFilter_packageComAndroidSystemui_dropped() {
        val sbn = statusBarNotification(packageName = "com.android.systemui", notification = plainNotification())

        assertFalse(NotificationFilter.shouldForward(sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun defaultFilter_packageAndroid_dropped() {
        val sbn = statusBarNotification(packageName = "android", notification = plainNotification())

        assertFalse(NotificationFilter.shouldForward(sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun defaultFilter_ordinaryAppPlainPost_forwarded() {
        val sbn = statusBarNotification(packageName = "com.example.chat", notification = plainNotification())

        assertTrue(NotificationFilter.shouldForward(sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun rejectionReason_ordinaryAppPlainPost_nullSoNothingIsFilteredByDefault() {
        val sbn = statusBarNotification(packageName = "com.example.chat", notification = plainNotification())

        assertNull(NotificationFilter.rejectionReason(sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun rejectionReason_droppedNotifications_carryLogSafeReasonCodes() {
        val own = statusBarNotification(packageName = OWN_PACKAGE, notification = plainNotification())
        val noise = statusBarNotification(packageName = "android", notification = plainNotification())

        assertEquals("own_app", NotificationFilter.rejectionReason(own, ownPackageName = OWN_PACKAGE))
        assertEquals("system_noise", NotificationFilter.rejectionReason(noise, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun defaultFilter_foregroundServiceFlag_dropped() {
        val notification = plainNotification()
        notification.flags = notification.flags or Notification.FLAG_FOREGROUND_SERVICE
        val sbn = statusBarNotification(packageName = "com.example.chat", notification = notification)

        assertFalse(NotificationFilter.shouldForward(sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun defaultFilter_groupSummaryWithTwoChildren_summaryDroppedChildrenForwarded() {
        val summary =
            Notification
                .Builder(context, CHANNEL_ID)
                .setGroup("group-key")
                .setGroupSummary(true)
                .build()
        val child1 = Notification.Builder(context, CHANNEL_ID).setGroup("group-key").build()
        val child2 = Notification.Builder(context, CHANNEL_ID).setGroup("group-key").build()

        val summarySbn = statusBarNotification(packageName = "com.example.chat", notification = summary)
        val child1Sbn = statusBarNotification(packageName = "com.example.chat", notification = child1)
        val child2Sbn = statusBarNotification(packageName = "com.example.chat", notification = child2)

        assertFalse(NotificationFilter.shouldForward(summarySbn, ownPackageName = OWN_PACKAGE))
        assertTrue(NotificationFilter.shouldForward(child1Sbn, ownPackageName = OWN_PACKAGE))
        assertTrue(NotificationFilter.shouldForward(child2Sbn, ownPackageName = OWN_PACKAGE))
    }

    @Test
    fun defaultFilter_mediaStyleTemplate_dropped() {
        val notification =
            Notification
                .Builder(context, CHANNEL_ID)
                .setStyle(Notification.MediaStyle())
                .build()
        val sbn = statusBarNotification(packageName = "com.example.player", notification = notification)

        assertFalse(NotificationFilter.shouldForward(sbn, ownPackageName = OWN_PACKAGE))
    }

    private fun plainNotification(): Notification =
        Notification
            .Builder(context, CHANNEL_ID)
            .setContentTitle("Alice")
            .setContentText("On my way")
            .build()

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
        const val OWN_PACKAGE = "dev.tandem.app"
    }
}
