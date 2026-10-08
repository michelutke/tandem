package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

@RunWith(AndroidJUnit4::class)
class ClipboardCaptureServiceTest {
    private var captures = 0
    private var enabled = true
    private var hasSession = true
    private val service =
        Robolectric.buildService(ClipboardCaptureService::class.java).get().also {
            it.startCapture = { captures++ }
            it.gate = AutoCaptureGate({ enabled }, { hasSession }, { 0L })
        }

    private fun copyOverlayEvent(): AccessibilityEvent =
        AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED).apply {
            packageName = CopyEventFilter.SYSTEM_UI_PACKAGE
            className = "com.android.systemui.clipboardoverlay.ClipboardOverlayActivity"
        }

    @Test
    fun onAccessibilityEvent_copyOverlayWithSettingOn_startsOverlayCapture() {
        service.onAccessibilityEvent(copyOverlayEvent())

        assertEquals(1, captures)
    }

    @Test
    fun onAccessibilityEvent_settingOff_doesNothing() {
        enabled = false

        service.onAccessibilityEvent(copyOverlayEvent())

        assertEquals(0, captures)
    }

    @Test
    fun onAccessibilityEvent_noSession_doesNothing() {
        hasSession = false
        LiveClipboardSession.current = null

        service.onAccessibilityEvent(copyOverlayEvent())

        assertEquals(0, captures)
    }

    @Test
    fun onAccessibilityEvent_unrelatedEvent_doesNothing() {
        val event =
            AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED).apply {
                packageName =
                    "com.example"
            }

        service.onAccessibilityEvent(event)

        assertEquals(0, captures)
    }
}
