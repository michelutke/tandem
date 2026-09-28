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
//   unit: shareTargetActivity_actionSendTextPlain_sendsClipboardTextOriginAndroid
//
// Runs on Robolectric (E00-20): ShareTargetActivity is an Activity, an unavoidable Android
// framework type. sessionProvider/dispatcher are set on the built-but-not-yet-created instance
// (same seam convention BootReceiverTest uses for BootReceiver.serviceStarterFactory/dispatcher),
// UnconfinedTestDispatcher runs ClipboardSender.send synchronously so onCreate's launch block
// (including the finish() it calls) completes before Robolectric's create() returns.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class ShareTargetActivityTest {
    @Test
    fun shareTargetActivity_actionSendTextPlain_sendsClipboardTextOriginAndroid() {
        val session = FakeTandemSession()
        val intent =
            explicitIntent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, "hello mac")
            }

        val activity = buildAndCreate(intent, session)

        val sent = session.sentFrames.single().clipboardText
        assertEquals("android", sent.originTag)
        assertEquals("hello mac", sent.text)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun shareTargetActivity_missingExtraText_sendsNothing() {
        val session = FakeTandemSession()
        val intent = explicitIntent(Intent.ACTION_SEND).apply { type = "text/plain" }

        buildAndCreate(intent, session)

        assertTrue(session.sentFrames.isEmpty())
    }

    // Explicit (setClass) rather than a bare implicit Intent(action): detekt's
    // ImplicitInternalIntent rule requires an explicit target, and Robolectric.buildActivity's
    // second argument is delivered straight to the built ShareTargetActivity regardless, so
    // setting the class here changes nothing about what onCreate() sees.
    private fun explicitIntent(action: String): Intent =
        Intent(action).setClass(ApplicationProvider.getApplicationContext(), ShareTargetActivity::class.java)

    private fun buildAndCreate(
        intent: Intent,
        session: FakeTandemSession,
    ): ShareTargetActivity {
        val controller = Robolectric.buildActivity(ShareTargetActivity::class.java, intent)
        val activity = controller.get()
        activity.sessionProvider = { session }
        activity.dispatcher = UnconfinedTestDispatcher()
        controller.create()
        return activity
    }
}
