package dev.tandem.feature.mirror

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.util.regex.Pattern

/**
 * E61-02 instrumented tdd, driving the real system consent dialog with UiAutomator (E00-21):
 * `projectionConsent_uiAutomatorTapsStartNow_projectionGranted` and
 * `projectionConsent_uiAutomatorTapsCancel_noVirtualDisplayCreated`. The Cancel case also asserts
 * the starter stays `NotStarted`; no code in this module creates a VirtualDisplay before consent.
 */
@RunWith(AndroidJUnit4::class)
class ProjectionConsentInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private var host: ConsentHostActivity? = null
    private var consentIntent: Intent? = null

    @Before
    fun wakeAndGoHome() {
        device.wakeUp()
        device.executeShellCommand("wm dismiss-keyguard")
        device.pressHome()
    }

    @After
    fun finishHost() {
        host?.let { instrumentation.runOnMainSync { it.finish() } }
        device.pressHome()
        device.wait(Until.gone(By.res(NEGATIVE_BUTTON_ID)), DIALOG_TIMEOUT_MS)
    }

    @Test
    fun projectionConsent_uiAutomatorTapsStartNow_projectionGranted() {
        val (starter, host) = startConsent()

        awaitConsentDialog(host)
        selectEntireScreenIfOffered()
        tap(By.res(POSITIVE_BUTTON_ID), By.text(START_LABEL))
        awaitResult(host)
        starter.onConsentResult(granted = host.resultCode == Activity.RESULT_OK)

        assertEquals(Activity.RESULT_OK, host.resultCode)
        assertEquals(MirrorSessionState.ConsentGranted, starter.state)
    }

    @Test
    fun projectionConsent_uiAutomatorTapsCancel_noVirtualDisplayCreated() {
        val (starter, host) = startConsent()

        awaitConsentDialog(host)
        tap(By.res(NEGATIVE_BUTTON_ID), By.text(CANCEL_LABEL))
        assertTrue(
            "consent dialog still shown after cancel",
            device.wait(Until.gone(By.res(NEGATIVE_BUTTON_ID)), DIALOG_TIMEOUT_MS),
        )
        awaitResult(host)
        val resultCode = host.resultCode ?: Activity.RESULT_CANCELED
        starter.onConsentResult(granted = resultCode == Activity.RESULT_OK)

        assertEquals(Activity.RESULT_CANCELED, resultCode)
        assertEquals(MirrorSessionState.NotStarted, starter.state)
    }

    private fun startConsent(): Pair<MirrorSessionStarter, ConsentHostActivity> {
        val context = instrumentation.targetContext
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val hostIntent =
            Intent(context, ConsentHostActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val monitor = Instrumentation.ActivityMonitor(ConsentHostActivity::class.java.name, null, false)
        instrumentation.addMonitor(monitor)
        context.startActivity(hostIntent)
        val host =
            requireNotNull(monitor.waitForActivityWithTimeout(DIALOG_TIMEOUT_MS) as? ConsentHostActivity) {
                "ConsentHostActivity not started"
            }
        this.host = host
        val starter =
            MirrorSessionStarter(
                MediaProjectionConsentLauncher(manager) { intent ->
                    consentIntent = intent
                    instrumentation.runOnMainSync { host.launchForResult(intent) }
                },
            )
        starter.onLocalStartAction()
        return starter to host
    }

    // Android 14+ asks single app vs entire screen first; only entire screen is a full-screen consent.
    private fun selectEntireScreenIfOffered() {
        val spinner = device.wait(Until.findObject(By.res(SHARE_MODE_SPINNER_ID)), SPINNER_TIMEOUT_MS) ?: return
        spinner.click()
        val entireScreen = device.wait(Until.findObject(By.text(ENTIRE_SCREEN)), DIALOG_TIMEOUT_MS)
        assertNotNull("entire screen option not shown", entireScreen)
        entireScreen.click()
    }

    // SystemUI can restart on a loaded emulator and drop the dialog, so ask again before failing.
    private fun awaitConsentDialog(host: ConsentHostActivity) {
        val intent = requireNotNull(consentIntent) { "consent intent not captured" }
        repeat(DIALOG_ATTEMPTS) {
            val deadline = System.currentTimeMillis() + DIALOG_ATTEMPT_MS
            while (System.currentTimeMillis() < deadline) {
                if (isConsentDialogShown()) return
                device.waitForIdle(DIALOG_POLL_MS)
            }
            instrumentation.runOnMainSync { host.relaunchForResult(intent) }
        }
        if (isConsentDialogShown()) return
        dumpHierarchy()
        fail("consent dialog not shown after $DIALOG_ATTEMPTS attempts")
    }

    private fun isConsentDialogShown(): Boolean =
        device.hasObject(By.res(POSITIVE_BUTTON_ID)) || device.hasObject(By.text(START_LABEL))

    private fun dumpHierarchy() {
        val dump = ByteArrayOutputStream()
        device.dumpWindowHierarchy(dump)
        Log.e(TAG, "window hierarchy at failure:\n$dump")
    }

    private fun tap(
        byId: BySelector,
        byText: BySelector,
    ) {
        val button =
            device.wait(Until.findObject(byId), DIALOG_TIMEOUT_MS)
                ?: device.wait(Until.findObject(byText), DIALOG_TIMEOUT_MS)
        if (button == null) dumpHierarchy()
        assertNotNull("consent dialog button not shown", button)
        button.click()
    }

    private fun awaitResult(host: ConsentHostActivity) {
        val delivered = host.awaitResult(DIALOG_TIMEOUT_MS)
        if (!delivered) dumpHierarchy()
        assertTrue("consent result not delivered", delivered)
    }

    private companion object {
        const val POSITIVE_BUTTON_ID = "android:id/button1"
        const val NEGATIVE_BUTTON_ID = "android:id/button2"
        const val SHARE_MODE_SPINNER_ID = "com.android.systemui:id/screen_share_mode_spinner"
        const val DIALOG_TIMEOUT_MS = 30_000L
        const val DIALOG_ATTEMPT_MS = 15_000L
        const val DIALOG_ATTEMPTS = 3
        const val DIALOG_POLL_MS = 500L
        const val TAG = "ProjectionConsentTest"
        const val SPINNER_TIMEOUT_MS = 5_000L
        val START_LABEL: Pattern = Pattern.compile("(?i)start( now)?|next")
        val CANCEL_LABEL: Pattern = Pattern.compile("(?i)cancel")
        val ENTIRE_SCREEN: Pattern = Pattern.compile("(?i)(share )?entire screen")
    }
}
