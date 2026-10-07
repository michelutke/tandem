package dev.tandem.feature.clipboard

import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.transport.TandemSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

@RunWith(AndroidJUnit4::class)
class ClipboardCaptureServiceTest {
    private val launched = mutableListOf<Intent>()
    private var enabled = true
    private var hasSession = true
    private val service =
        Robolectric.buildService(ClipboardCaptureService::class.java).get().also {
            it.launcher = { intent -> launched += intent }
            it.gate = AutoCaptureGate({ enabled }, { hasSession }, { 0L })
        }

    private fun copyOverlayEvent(): AccessibilityEvent =
        AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED).apply {
            packageName = CopyEventFilter.SYSTEM_UI_PACKAGE
            className = "com.android.systemui.clipboardoverlay.ClipboardOverlayActivity"
        }

    @Test
    fun onAccessibilityEvent_copyOverlayWithSettingOn_launchesAutoCapture() {
        service.onAccessibilityEvent(copyOverlayEvent())

        val intent = launched.single()
        assertEquals(ClipboardCaptureActivity::class.java.name, intent.component?.className)
    }

    @Test
    fun onAccessibilityEvent_settingOff_doesNothing() {
        enabled = false

        service.onAccessibilityEvent(copyOverlayEvent())

        assertTrue(launched.isEmpty())
    }

    @Test
    fun onAccessibilityEvent_noSession_doesNothing() {
        hasSession = false
        LiveClipboardSession.current = null

        service.onAccessibilityEvent(copyOverlayEvent())

        assertTrue(launched.isEmpty())
    }

    @Test
    fun onAccessibilityEvent_unrelatedEvent_doesNothing() {
        val event =
            AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED).apply {
                packageName =
                    "com.example"
            }

        service.onAccessibilityEvent(event)

        assertTrue(launched.isEmpty())
    }
}
