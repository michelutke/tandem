package dev.tandem.feature.clipboard

import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

// E31-12 tdd:
//   unit: clipboardCaptureActivity_windowFocusWithTextClip_sendsClipAndFinishes
//   unit: clipboardCaptureActivity_emptyClipboard_sendsNothing
//
// Runs on Robolectric (E00-20); see ShareTargetActivityTest's header for the seam/dispatcher
// convention this test shares with it.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class ClipboardCaptureActivityTest {
    @Test
    fun clipboardCaptureActivity_windowFocusWithTextClip_sendsClipAndFinishes() {
        val session = FakeTandemSession()

        val activity = buildAndFocus(ClipboardReader { ClipboardClip("copied text", sensitive = false) }, session)

        val sent = session.sentFrames.single().clipboardText
        assertEquals("android", sent.originTag)
        assertEquals("copied text", sent.text)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun clipboardCaptureActivity_emptyClipboard_sendsNothing() {
        val session = FakeTandemSession()

        val activity = buildAndFocus(ClipboardReader { null }, session)

        assertTrue(session.sentFrames.isEmpty())
        assertTrue(activity.isFinishing)
    }

    @Test
    fun clipboardCaptureActivity_noWindowFocus_doesNotReadClipboard() {
        val session = FakeTandemSession()
        var reads = 0
        val controller = Robolectric.buildActivity(ClipboardCaptureActivity::class.java, captureIntent())
        val activity = controller.get()
        activity.sessionProvider = { session }
        activity.dispatcher = UnconfinedTestDispatcher()
        activity.clipboardReaderProvider = {
            ClipboardReader {
                reads++
                ClipboardClip("copied text", sensitive = false)
            }
        }
        controller.create()

        activity.onWindowFocusChanged(false)

        assertEquals(0, reads)
        assertTrue(session.sentFrames.isEmpty())
    }

    private fun captureIntent(): Intent =
        Intent().setClass(ApplicationProvider.getApplicationContext(), ClipboardCaptureActivity::class.java)

    private fun buildAndFocus(
        reader: ClipboardReader,
        session: FakeTandemSession,
    ): ClipboardCaptureActivity {
        val controller = Robolectric.buildActivity(ClipboardCaptureActivity::class.java, captureIntent())
        val activity = controller.get()
        activity.sessionProvider = { session }
        activity.dispatcher = UnconfinedTestDispatcher()
        activity.clipboardReaderProvider = { reader }
        controller.create()
        activity.onWindowFocusChanged(true)
        return activity
    }
}
