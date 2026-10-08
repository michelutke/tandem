package dev.tandem.feature.notifications

import android.app.Notification
import android.content.Context
import android.os.Process
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.protocol.v1.NotificationDismiss
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment

/**
 * `TandemNotificationListenerService` E30-10 tests (`docs/planning/backlog/phase-3.yaml` E30-10's
 * `tdd:` list). Robolectric (E00-20): `StatusBarNotification`/`RankingMap` are Android framework
 * types, so the reason-less-vs-reasoned `onNotificationRemoved` distinction is unavoidable here.
 * `eventSink` is substituted with a recording fake, the same seam convention `NotificationMapperTest`
 * and `NotificationSinkTest` rely on elsewhere in this module.
 */
@RunWith(AndroidJUnit4::class)
class TandemNotificationListenerServiceTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun androidDismissSync_removedReasonCancel_sendsDismissOriginAndroid() {
        val service = newService()
        val sink = RecordingEventSink()
        service.eventSink = sink
        val sbn = statusBarNotification("swiped-key")

        service.onNotificationRemoved(sbn, emptyRankingMap(), NotificationListenerService.REASON_CANCEL)

        assertEquals(1, sink.dismissed.size)
        assertEquals(sbn.key, sink.dismissed.single().key)
        assertEquals(NotificationDismiss.Origin.ORIGIN_ANDROID, sink.dismissed.single().origin)
    }

    @Test
    fun androidDismissSync_removedReasonListenerCancel_sendsNoDismiss() {
        val service = newService()
        val sink = RecordingEventSink()
        service.eventSink = sink
        val sbn = statusBarNotification("mac-cancelled-key")

        service.onNotificationRemoved(
            sbn,
            emptyRankingMap(),
            NotificationListenerService.REASON_LISTENER_CANCEL,
        )

        assertTrue(sink.dismissed.isEmpty())
    }

    @After
    fun clearInstalledFilter() {
        LiveNotificationListener.filter = null
    }

    @Test
    fun perAppFilter_installedFilterDeniesPackage_notificationNeverForwarded() {
        val service = newService()
        val sink = RecordingEventSink()
        service.eventSink = sink
        LiveNotificationListener.filter = { sbn, _ -> sbn.packageName != "com.example.chat" }

        service.onNotificationPosted(statusBarNotification("denied-key"))

        assertTrue(sink.posted.isEmpty())
    }

    @Test
    fun perAppFilter_installedFilterAllowsPackage_notificationForwarded() {
        val service = newService()
        val sink = RecordingEventSink()
        service.eventSink = sink
        LiveNotificationListener.filter = { _, _ -> true }

        service.onNotificationPosted(statusBarNotification("allowed-key"))

        assertEquals(1, sink.posted.size)
    }

    private fun newService(): TandemNotificationListenerService =
        Robolectric.buildService(TandemNotificationListenerService::class.java).create().get()

    // NotificationListenerService.RankingMap(Ranking[]) is @hide (compile-time android.jar only
    // exposes the no-arg constructor); Robolectric's runtime jar restores it, so reflection is the
    // only way to construct a non-null RankingMap for this test.
    private fun emptyRankingMap(): NotificationListenerService.RankingMap {
        val ctor =
            NotificationListenerService.RankingMap::class.java.getDeclaredConstructor(
                Array<NotificationListenerService.Ranking>::class.java,
            )
        ctor.isAccessible = true
        return ctor.newInstance(arrayOf<NotificationListenerService.Ranking>())
    }

    @Suppress("DEPRECATION")
    private fun statusBarNotification(key: String): StatusBarNotification =
        StatusBarNotification(
            "com.example.chat",
            "com.example.chat",
            1,
            key,
            Process.myUid(),
            Process.myPid(),
            0,
            Notification.Builder(context, CHANNEL_ID).build(),
            Process.myUserHandle(),
            System.currentTimeMillis(),
        )

    private class RecordingEventSink : NotificationEventSink {
        val dismissed = mutableListOf<NotificationDismiss>()
        val posted = mutableListOf<dev.tandem.protocol.v1.NotificationPosted>()

        override fun onNotificationPosted(notification: dev.tandem.protocol.v1.NotificationPosted) {
            posted += notification
        }

        override fun onNotificationDismissed(dismiss: NotificationDismiss) {
            dismissed += dismiss
        }
    }

    private companion object {
        const val CHANNEL_ID = "test-channel"
    }
}
