package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** ADR-007 copy-detection filter. Plain JUnit5. */
class CopyEventFilterTest {
    private val windowState = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED

    @Test
    fun isCopyOverlay_systemUiClipboardWindow_isCopy() {
        assertTrue(
            CopyEventFilter.isCopyOverlay(
                "com.android.systemui",
                windowState,
                "com.android.systemui.clipboardoverlay.ClipboardOverlayActivity",
                emptyList(),
            ),
        )
    }

    @Test
    fun isCopyOverlay_systemUiCopiedText_isCopy() {
        assertTrue(CopyEventFilter.isCopyOverlay("com.android.systemui", windowState, null, listOf("Copied")))
    }

    @Test
    fun isCopyOverlay_otherPackage_isNotCopy() {
        assertFalse(CopyEventFilter.isCopyOverlay("com.example.app", windowState, "ClipboardView", listOf("Copied")))
    }

    @Test
    fun isCopyOverlay_otherEventType_isNotCopy() {
        val contentChanged = AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED

        assertFalse(
            CopyEventFilter.isCopyOverlay("com.android.systemui", contentChanged, "ClipboardOverlay", emptyList()),
        )
    }

    @Test
    fun isCopyOverlay_unrelatedSystemUiWindow_isNotCopy() {
        assertFalse(
            CopyEventFilter.isCopyOverlay("com.android.systemui", windowState, "NotificationShade", listOf("Wi-Fi")),
        )
    }
}
