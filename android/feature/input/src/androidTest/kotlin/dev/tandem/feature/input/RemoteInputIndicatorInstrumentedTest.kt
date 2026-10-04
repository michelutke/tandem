package dev.tandem.feature.input

import android.graphics.PixelFormat
import android.view.View
import android.view.WindowManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.swipe
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.FileInputStream

// E62-06 tdd:
//   instrumented: remoteInputIndicator_remoteSwipeOverNotification_indicatorStillPosted
//   instrumented: remoteInputIndicator_otherAppOverlayShown_accessibilityOverlayStaysTopmost
@RunWith(AndroidJUnit4::class)
class RemoteInputIndicatorInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.context
    private val serviceComponent = "${context.packageName}/${CapturingAccessibilityService::class.java.name}"
    private lateinit var indicator: RemoteInputIndicator
    private lateinit var service: CapturingAccessibilityService

    @Before
    fun enableServiceAndShowIndicator() {
        shell("settings put secure enabled_accessibility_services $serviceComponent")
        shell("settings put secure accessibility_enabled 1")
        awaitService()
        service = checkNotNull(CapturingAccessibilityService.instance)
        indicator = RemoteInputIndicator(AndroidNotificationPresenter(context), AccessibilityOverlayBadge(service))
        assertTrue(indicator.show())
    }

    @After
    fun hideIndicatorAndDisableService() {
        indicator.hide()
        shell("settings put secure enabled_accessibility_services \"\"")
        shell("settings put secure accessibility_enabled 0")
    }

    @Test
    fun remoteInputIndicator_remoteSwipeOverNotification_indicatorStillPosted() {
        shell("cmd statusbar expand-notifications")
        Thread.sleep(SETTLE_MS)
        val screen = Size(context.resources.displayMetrics.widthPixels, context.resources.displayMetrics.heightPixels)
        val event =
            swipe {
                x1 = screen.width * 9 / 10
                y1 = screen.height / 4
                x2 = screen.width / 10
                y2 = screen.height / 4
                durationMs = SWIPE_MS
            }

        GestureTranslator(ServiceAccessibilityActions(service)).handle(event, screen, screen)
        Thread.sleep(SETTLE_MS)

        assertTrue(indicator.isShowing())
        shell("cmd statusbar collapse")
    }

    @Test
    fun remoteInputIndicator_otherAppOverlayShown_accessibilityOverlayStaysTopmost() {
        shell("appops set ${context.packageName} SYSTEM_ALERT_WINDOW allow")
        val windowManager = context.getSystemService(WindowManager::class.java)
        val otherAppOverlay = View(context)
        val params =
            WindowManager
                .LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT,
                ).apply { title = OTHER_OVERLAY_TITLE }
        instrumentation.runOnMainSync { windowManager.addView(otherAppOverlay, params) }
        try {
            Thread.sleep(SETTLE_MS)
            val dump = shell("dumpsys window windows")
            val badgeIndex = dump.indexOf(AccessibilityOverlayBadge.WINDOW_TITLE)
            val otherIndex = dump.indexOf(OTHER_OVERLAY_TITLE)

            assertTrue(indicator.isShowing())
            assertTrue(badgeIndex >= 0 && otherIndex >= 0)
            assertEquals("badge window must be listed above the app overlay", true, badgeIndex < otherIndex)
        } finally {
            instrumentation.runOnMainSync { windowManager.removeView(otherAppOverlay) }
        }
    }

    private fun awaitService() {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (CapturingAccessibilityService.instance == null && System.currentTimeMillis() < deadline) {
            Thread.sleep(POLL_MS)
        }
        checkNotNull(CapturingAccessibilityService.instance) { "accessibility service not connected" }
    }

    private fun shell(command: String): String =
        FileInputStream(instrumentation.uiAutomation.executeShellCommand(command).fileDescriptor).use {
            it.readBytes().decodeToString()
        }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        const val POLL_MS = 200L
        const val SETTLE_MS = 1_000L
        const val SWIPE_MS = 200
        const val OTHER_OVERLAY_TITLE = "OtherAppOverlay"
    }
}
