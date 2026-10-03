package dev.tandem.feature.files

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E40-12 tdd:
//   unit: androidProgressNotification_fortyTwoPercent_progressBarAt42
@RunWith(AndroidJUnit4::class)
class TransferProgressNotifierTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager = context.getSystemService(NotificationManager::class.java)

    @Test
    fun androidProgressNotification_fortyTwoPercent_progressBarAt42() {
        TransferProgressNotifier(context).post("t-1", TransferProgress(percent = 42, bytesPerSecond = 2048))

        val notification = shadowOf(manager).getNotification("t-1", TransferProgressNotifier.NOTIFICATION_ID)
        assertEquals(42, notification.extras.getInt(Notification.EXTRA_PROGRESS))
        assertEquals(100, notification.extras.getInt(Notification.EXTRA_PROGRESS_MAX))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(listOf("Cancel"), notification.actions.map { it.title.toString() })
    }

    @Test
    fun androidProgressNotification_cancel_removesNotification() {
        val notifier = TransferProgressNotifier(context)
        notifier.post("t-1", TransferProgress(percent = 10, bytesPerSecond = 0))

        notifier.cancel("t-1")

        assertEquals(null, shadowOf(manager).getNotification("t-1", TransferProgressNotifier.NOTIFICATION_ID))
    }
}
