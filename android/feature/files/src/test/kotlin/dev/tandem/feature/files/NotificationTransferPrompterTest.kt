package dev.tandem.feature.files

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E40-07 tdd:
//   unit: androidAcceptPrompt_offerPosted_notificationHasAcceptAndDeclineActions
//
// Robolectric (E00-20): Notification/NotificationManager are unavoidable framework types.
@RunWith(AndroidJUnit4::class)
class NotificationTransferPrompterTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager = context.getSystemService(NotificationManager::class.java)

    @Test
    fun androidAcceptPrompt_offerPosted_notificationHasAcceptAndDeclineActions() {
        NotificationTransferPrompter(context).post("offer-1", "report.pdf", 2048)

        val notification = shadowOf(manager).getNotification("offer-1", NotificationTransferPrompter.NOTIFICATION_ID)
        assertEquals(listOf("Accept", "Decline"), notification.actions.map { it.title.toString() })
        val text = notification.extras.getCharSequence("android.text").toString()
        assertTrue(text.startsWith("report.pdf ("))
    }

    @Test
    fun androidAcceptPrompt_cancel_removesNotification() {
        val prompter = NotificationTransferPrompter(context)
        prompter.post("offer-1", "report.pdf", 2048)

        prompter.cancel("offer-1")

        assertEquals(null, shadowOf(manager).getNotification("offer-1", NotificationTransferPrompter.NOTIFICATION_ID))
    }
}
