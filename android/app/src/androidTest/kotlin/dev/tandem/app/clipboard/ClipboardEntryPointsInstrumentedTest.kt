package dev.tandem.app.clipboard

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.MainActivity
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.feature.clipboard.ClipboardCaptureActivity
import dev.tandem.feature.clipboard.ClipboardClip
import dev.tandem.feature.clipboard.ClipboardReader
import dev.tandem.feature.clipboard.ProcessTextActivity
import dev.tandem.feature.clipboard.ShareTargetActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// E31-12 tdd:
//   instrumented: clipboardEntryPoints_api33And35NoAccessibility_eachSendsOneClip
//
// Runs on the api33 and api35 managed devices (E00-21) with no AccessibilityService enabled
// (asserted below). Each UC-13 entry point -- share target, PROCESS_TEXT, the QS tile's capture
// activity, and the in-app button -- must produce exactly one ClipboardText send. No production
// composition root wires a live TandemSession yet, so the FakeTandemSession is injected through
// each entry point's sessionProvider seam in onActivityPreCreated, before onCreate reads it. The
// capture activity and MainActivity read a scripted ClipboardReader instead of the system
// clipboard, which an instrumented test process may not read without window focus.
@RunWith(AndroidJUnit4::class)
class ClipboardEntryPointsInstrumentedTest {
    private val application = ApplicationProvider.getApplicationContext<Application>()

    @Test
    fun clipboardEntryPoints_api33And35NoAccessibility_eachSendsOneClip() {
        assertNoAccessibilityServiceEnabled()

        assertOneClip("shared text") { session ->
            launchWithSession<ShareTargetActivity>(
                Intent(Intent.ACTION_SEND).setClass(application, ShareTargetActivity::class.java).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, "shared text")
                },
            ) { it.sessionProvider = { session } }
        }
        assertOneClip("selected text") { session ->
            launchWithSession<ProcessTextActivity>(
                Intent(Intent.ACTION_PROCESS_TEXT).setClass(application, ProcessTextActivity::class.java).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_PROCESS_TEXT, "selected text")
                },
            ) { it.sessionProvider = { session } }
        }
        assertOneClip("tile text") { session ->
            launchWithSession<ClipboardCaptureActivity>(
                Intent(application, ClipboardCaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            ) {
                it.sessionProvider = { session }
                it.clipboardReaderProvider = { ClipboardReader { ClipboardClip("tile text", sensitive = false) } }
            }
        }
        assertOneClip("button text") { session ->
            var armed = false
            val scenario =
                launchWithSession<MainActivity>(
                    Intent(application, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                ) {
                    it.sessionProvider = { session }
                    it.clipboardReaderProvider = {
                        ClipboardReader { if (armed) ClipboardClip("button text", sensitive = false) else null }
                    }
                }
            waitUntil {
                var focused = false
                scenario.onActivity { focused = it.hasWindowFocus() }
                focused
            }
            armed = true
            scenario.onActivity { it.onSendClipboardButtonTapped() }
            scenario
        }
    }

    private fun assertNoAccessibilityServiceEnabled() {
        val enabled =
            Settings.Secure
                .getString(application.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                .orEmpty()
        assertFalse("expected no Tandem AccessibilityService enabled", enabled.contains(application.packageName))
    }

    private fun assertOneClip(
        expectedText: String,
        launch: (FakeTandemSession) -> ActivityScenario<*>,
    ) {
        val session = FakeTandemSession()
        launch(session).use {
            waitUntil { session.sentFrames.isNotEmpty() }
            val sent = session.sentFrames.single().clipboardText
            assertEquals(expectedText, sent.text)
            assertEquals("android", sent.originTag)
        }
    }

    private inline fun <reified A : Activity> launchWithSession(
        intent: Intent,
        crossinline configure: (A) -> Unit,
    ): ActivityScenario<A> {
        val callbacks =
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityPreCreated(
                    activity: Activity,
                    savedInstanceState: Bundle?,
                ) {
                    if (activity is A) configure(activity)
                }

                override fun onActivityCreated(
                    activity: Activity,
                    savedInstanceState: Bundle?,
                ) = Unit

                override fun onActivityStarted(activity: Activity) = Unit

                override fun onActivityResumed(activity: Activity) = Unit

                override fun onActivityPaused(activity: Activity) = Unit

                override fun onActivityStopped(activity: Activity) = Unit

                override fun onActivitySaveInstanceState(
                    activity: Activity,
                    outState: Bundle,
                ) = Unit

                override fun onActivityDestroyed(activity: Activity) = Unit
            }
        application.registerActivityLifecycleCallbacks(callbacks)
        return try {
            ActivityScenario.launch<A>(intent)
        } finally {
            application.unregisterActivityLifecycleCallbacks(callbacks)
        }
    }

    private fun waitUntil(condition: () -> Boolean) {
        val deadline = System.nanoTime() + TIMEOUT_NANOS
        while (!condition() && System.nanoTime() < deadline) Thread.sleep(POLL_MILLIS)
        assertTrue("timed out waiting for a clipboard send", condition())
    }

    private companion object {
        const val TIMEOUT_NANOS = 10_000_000_000L
        const val POLL_MILLIS = 50L
    }
}
