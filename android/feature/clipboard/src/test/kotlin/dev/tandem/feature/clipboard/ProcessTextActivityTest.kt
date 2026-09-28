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

// E31-06 tdd:
//   unit: processTextActivity_extraProcessText_sendsSelectedText
//   unit: processTextActivity_nonCharSequenceExtra_sendsNothing
//
// Runs on Robolectric (E00-20); see ShareTargetActivityTest's header for the seam/dispatcher
// convention this test shares with it.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class ProcessTextActivityTest {
    @Test
    fun processTextActivity_extraProcessText_sendsSelectedText() {
        val session = FakeTandemSession()
        val intent =
            explicitIntent(Intent.ACTION_PROCESS_TEXT).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_PROCESS_TEXT, "selected text")
            }

        val activity = buildAndCreate(intent, session)

        val sent = session.sentFrames.single().clipboardText
        assertEquals("android", sent.originTag)
        assertEquals("selected text", sent.text)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun processTextActivity_nonCharSequenceExtra_sendsNothing() {
        val session = FakeTandemSession()
        val intent =
            explicitIntent(Intent.ACTION_PROCESS_TEXT).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_PROCESS_TEXT, 42)
            }

        buildAndCreate(intent, session)

        assertTrue(session.sentFrames.isEmpty())
    }

    @Test
    fun processTextActivity_readonlyExtraOnly_sendsNothing() {
        val session = FakeTandemSession()
        val intent =
            explicitIntent(Intent.ACTION_PROCESS_TEXT).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
                putExtra("com.example.unrelated", "selected text")
            }

        buildAndCreate(intent, session)

        assertTrue(session.sentFrames.isEmpty())
    }

    // Explicit (setClass) rather than a bare implicit Intent(action): detekt's
    // ImplicitInternalIntent rule requires an explicit target, and Robolectric.buildActivity's
    // second argument is delivered straight to the built ProcessTextActivity regardless, so
    // setting the class here changes nothing about what onCreate() sees.
    private fun explicitIntent(action: String): Intent =
        Intent(action).setClass(ApplicationProvider.getApplicationContext(), ProcessTextActivity::class.java)

    private fun buildAndCreate(
        intent: Intent,
        session: FakeTandemSession,
    ): ProcessTextActivity {
        val controller = Robolectric.buildActivity(ProcessTextActivity::class.java, intent)
        val activity = controller.get()
        activity.sessionProvider = { session }
        activity.dispatcher = UnconfinedTestDispatcher()
        controller.create()
        return activity
    }
}
