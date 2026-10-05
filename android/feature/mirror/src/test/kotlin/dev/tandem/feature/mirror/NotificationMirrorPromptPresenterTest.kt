package dev.tandem.feature.mirror

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// Robolectric (E00-20): Notification/NotificationManager are unavoidable framework types.
@RunWith(AndroidJUnit4::class)
class NotificationMirrorPromptPresenterTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager = context.getSystemService(NotificationManager::class.java)

    @Test
    fun mirrorPrompt_show_postsStartAndDeclineActions() {
        NotificationMirrorPromptPresenter(context, Activity::class.java).show("MacBook Pro")

        val notification = shadowOf(manager).getNotification(NotificationMirrorPromptPresenter.NOTIFICATION_ID)
        assertEquals("Mirror to MacBook Pro?", notification.extras.getCharSequence("android.title").toString())
        assertEquals(listOf("Start mirroring", "Not now"), notification.actions.map { it.title.toString() })
    }

    @Test
    fun mirrorPrompt_show_startActionOpensActivityNotBroadcast() {
        NotificationMirrorPromptPresenter(context, Activity::class.java).show("MacBook Pro")

        val notification = shadowOf(manager).getNotification(NotificationMirrorPromptPresenter.NOTIFICATION_ID)
        val start = shadowOf(notification.actions[0].actionIntent)
        assertTrue(start.isActivity)
        assertEquals(Activity::class.java.name, start.savedIntent.component?.className)
        assertTrue(shadowOf(notification.contentIntent).isActivity)
        assertTrue(shadowOf(notification.actions[1].actionIntent).isBroadcastIntent)
        assertTrue(shadowOf(notification.deleteIntent).isBroadcastIntent)
    }

    @Test
    fun mirrorPrompt_remove_cancelsNotification() {
        val presenter = NotificationMirrorPromptPresenter(context, Activity::class.java)
        presenter.show("MacBook Pro")

        presenter.remove()

        assertNull(shadowOf(manager).getNotification(NotificationMirrorPromptPresenter.NOTIFICATION_ID))
    }
}
