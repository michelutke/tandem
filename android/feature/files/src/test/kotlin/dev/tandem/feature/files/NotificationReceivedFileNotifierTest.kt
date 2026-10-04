package dev.tandem.feature.files

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E40-13 tdd:
//   unit: androidReceivedNotification_publishSucceeded_postedWithSanitizedName
//   unit: androidReceivedNotification_contentIntent_viewsMediaStoreUriWithReadGrant
//   unit: androidReceivedNotification_hashMismatch_noNotificationPosted (FileReceiverTest)
//
// Robolectric (E00-20): Notification/PendingIntent are unavoidable framework types.
@RunWith(AndroidJUnit4::class)
class NotificationReceivedFileNotifierTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val uri = "content://media/external/downloads/42"

    @Test
    fun androidReceivedNotification_publishSucceeded_postedWithSanitizedName() {
        NotificationReceivedFileNotifier(context).notifyReceived("report.pdf", "application/pdf", uri)

        val notifications = shadowOf(manager).allNotifications
        assertEquals(1, notifications.size)
        assertEquals(
            "report.pdf",
            notifications
                .single()
                .extras
                .getCharSequence("android.title")
                .toString(),
        )
    }

    @Test
    fun androidReceivedNotification_contentIntent_viewsMediaStoreUriWithReadGrant() {
        NotificationReceivedFileNotifier(context).notifyReceived("report.pdf", "application/pdf", uri)

        val notification = shadowOf(manager).getNotification(uri, NotificationReceivedFileNotifier.NOTIFICATION_ID)
        val pending = shadowOf(notification.contentIntent)
        val intent = pending.savedIntent
        assertTrue(pending.isActivity)
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals(uri, intent.data.toString())
        assertEquals("application/pdf", intent.type)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertNotNull(notification.contentIntent)
    }
}
