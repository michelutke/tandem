package dev.tandem.feature.mirror

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith

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

    @Test
    fun projectionConsent_uiAutomatorTapsStartNow_projectionGranted() {
        val (starter, host) = startConsent()

        tap(START_NOW)
        awaitResult(host)
        starter.onConsentResult(granted = host.resultCode == Activity.RESULT_OK)

        assertEquals(Activity.RESULT_OK, host.resultCode)
        assertEquals(MirrorSessionState.ConsentGranted, starter.state)
    }

    @Test
    fun projectionConsent_uiAutomatorTapsCancel_noVirtualDisplayCreated() {
        val (starter, host) = startConsent()

        tap(CANCEL)
        awaitResult(host)
        starter.onConsentResult(granted = host.resultCode == Activity.RESULT_OK)

        assertEquals(Activity.RESULT_CANCELED, host.resultCode)
        assertEquals(MirrorSessionState.NotStarted, starter.state)
    }

    private fun startConsent(): Pair<MirrorSessionStarter, ConsentHostActivity> {
        val context = instrumentation.targetContext
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val hostIntent =
            Intent(context, ConsentHostActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val host = instrumentation.startActivitySync(hostIntent) as ConsentHostActivity
        val starter =
            MirrorSessionStarter(
                MediaProjectionConsentLauncher(manager) { intent ->
                    instrumentation.runOnMainSync { host.launchForResult(intent) }
                },
            )
        starter.onLocalStartAction()
        return starter to host
    }

    private fun tap(label: String) {
        val button = device.wait(Until.findObject(By.text(label)), DIALOG_TIMEOUT_MS)
        assertNotNull("consent dialog button \"$label\" not shown", button)
        button.click()
    }

    private fun awaitResult(host: ConsentHostActivity) {
        val deadline = System.currentTimeMillis() + DIALOG_TIMEOUT_MS
        while (host.resultCode == null && System.currentTimeMillis() < deadline) Thread.sleep(POLL_MS)
    }

    private companion object {
        const val START_NOW = "Start now"
        const val CANCEL = "Cancel"
        const val DIALOG_TIMEOUT_MS = 10_000L
        const val POLL_MS = 100L
    }
}
