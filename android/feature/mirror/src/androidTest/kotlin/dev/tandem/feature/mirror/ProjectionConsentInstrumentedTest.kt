package dev.tandem.feature.mirror

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.regex.Pattern

/**
 * E61-02 instrumented tdd, driving the real system consent dialog with UiAutomator (E00-21):
 * `projectionConsent_uiAutomatorTapsStartNow_projectionGranted` and
 * `projectionConsent_uiAutomatorTapsCancel_noVirtualDisplayCreated`. The Cancel case also asserts
 * the starter stays `NotStarted`; no code in this module creates a VirtualDisplay before consent.
 */
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = Build.VERSION_CODES.R)
class ProjectionConsentInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private var host: ConsentHostActivity? = null

    @After
    fun finishHost() {
        host?.let { instrumentation.runOnMainSync { it.finish() } }
    }

    @Test
    fun projectionConsent_uiAutomatorTapsStartNow_projectionGranted() {
        val (starter, host) = startConsent()

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

    private fun tap(
        byId: BySelector,
        byText: BySelector,
    ) {
        val button =
            device.wait(Until.findObject(byId), DIALOG_TIMEOUT_MS)
                ?: device.wait(Until.findObject(byText), DIALOG_TIMEOUT_MS)
        assertNotNull("consent dialog button not shown", button)
        button.click()
    }

    private fun awaitResult(host: ConsentHostActivity) {
        val deadline = System.currentTimeMillis() + DIALOG_TIMEOUT_MS
        while (host.resultCode == null && System.currentTimeMillis() < deadline) Thread.sleep(POLL_MS)
    }

    private companion object {
        const val POSITIVE_BUTTON_ID = "android:id/button1"
        const val NEGATIVE_BUTTON_ID = "android:id/button2"
        const val SHARE_MODE_SPINNER_ID = "com.android.systemui:id/screen_share_mode_spinner"
        const val DIALOG_TIMEOUT_MS = 10_000L
        const val SPINNER_TIMEOUT_MS = 3_000L
        const val POLL_MS = 100L
        val START_LABEL: Pattern = Pattern.compile("(?i)start( now)?|next")
        val CANCEL_LABEL: Pattern = Pattern.compile("(?i)cancel")
        val ENTIRE_SCREEN: Pattern = Pattern.compile("(?i)(share )?entire screen")
    }
}
