package dev.tandem.feature.input

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class AndroidNotificationPresenterTest {
    private val application: Application = ApplicationProvider.getApplicationContext()
    private val manager = application.getSystemService(NotificationManager::class.java)
    private val presenter = AndroidNotificationPresenter(application)

    @Test
    fun remoteInputIndicator_sessionActive_ongoingNotificationPosted() {
        assertTrue(presenter.post())

        val posted = shadowOf(manager).allNotifications.single()
        assertTrue(posted.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(application.getString(R.string.remote_input_indicator_title), shadowOf(posted).contentTitle)
        assertTrue(presenter.isPosted())
    }

    @Test
    fun remoteInputIndicator_remove_notificationGone() {
        presenter.post()
        presenter.remove()
        assertTrue(shadowOf(manager).allNotifications.isEmpty())
        assertFalse(presenter.isPosted())
    }

    @Test
    fun remoteInputIndicator_beforePost_notPosted() {
        assertFalse(presenter.isPosted())
    }
}
