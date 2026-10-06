package dev.tandem.feature.input

import android.app.UiAutomation
import android.content.ComponentName
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.RequiresDevice
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.tap
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.FileInputStream

// E62-04 tdd:
//   manual: accessibilityGesture_remoteTapOnTestButton_oneClickRegistered
//
// Enables this test APK's CapturingAccessibilityService via `settings put secure` (E00-21), then
// drives the real ServiceAccessibilityActions through GestureTranslator with an identity mapping.
@RunWith(AndroidJUnit4::class)
class AccessibilityGestureInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.context
    private val serviceComponent = "${context.packageName}/${CapturingAccessibilityService::class.java.name}"

    @Before
    fun enableService() {
        shell("settings put secure enabled_accessibility_services $serviceComponent")
        shell("settings put secure accessibility_enabled 1")
        awaitService()
    }

    @After
    fun disableService() {
        shell("settings put secure enabled_accessibility_services \"\"")
        shell("settings put secure accessibility_enabled 0")
        awaitServiceUnbound()
    }

    @Test
    @RequiresDevice
    fun accessibilityGesture_remoteTapOnTestButton_oneClickRegistered() {
        val intent =
            Intent()
                .setComponent(ComponentName(context.packageName, ButtonTestActivity::class.java.name))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ActivityScenario.launch<ButtonTestActivity>(intent).use { scenario ->
            var centerX = 0
            var centerY = 0
            var screen = Size(1, 1)
            scenario.onActivity {
                val location = IntArray(2)
                it.button.getLocationOnScreen(location)
                centerX = location[0] + it.button.width / 2
                centerY = location[1] + it.button.height / 2
                screen = Size(it.resources.displayMetrics.widthPixels, it.resources.displayMetrics.heightPixels)
            }
            val translator =
                GestureTranslator(ServiceAccessibilityActions(checkNotNull(CapturingAccessibilityService.instance)))

            val result =
                translator.handle(
                    tap {
                        x = centerX
                        y = centerY
                    },
                    window = screen,
                    display = screen,
                )

            assertEquals(InputResult.Performed, result)
            var clicks = 0
            val deadline = System.currentTimeMillis() + TIMEOUT_MS
            while (clicks == 0 && System.currentTimeMillis() < deadline) {
                Thread.sleep(POLL_MS)
                scenario.onActivity { clicks = it.clickCount.get() }
            }
            Thread.sleep(POLL_MS)
            scenario.onActivity { clicks = it.clickCount.get() }
            assertEquals(1, clicks)
        }
    }

    private fun awaitServiceUnbound() {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (CapturingAccessibilityService.instance != null && System.currentTimeMillis() < deadline) {
            Thread.sleep(POLL_MS)
        }
        check(CapturingAccessibilityService.instance == null) { "accessibility service still bound" }
    }

    private fun awaitService() {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (CapturingAccessibilityService.instance == null && System.currentTimeMillis() < deadline) {
            Thread.sleep(POLL_MS)
        }
        checkNotNull(CapturingAccessibilityService.instance) { "accessibility service not connected" }
    }

    private fun shell(command: String): String =
        FileInputStream(
            instrumentation
                .getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
                .executeShellCommand(command)
                .fileDescriptor,
        ).use {
            it.readBytes().decodeToString()
        }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        const val POLL_MS = 200L
    }
}
