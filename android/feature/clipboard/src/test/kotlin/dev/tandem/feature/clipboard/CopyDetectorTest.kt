package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** ADR-007 toolbar-then-overlay copy detection. Plain JUnit5. */
class CopyDetectorTest {
    private var now = 0L
    private val detector = CopyDetector({ now })
    private val systemUi = "com.android.systemui"
    private val windowState = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
    private val toolbar = listOf<CharSequence>("Weitere Optionen", "Übersetzen", "Ausschneiden", "Kopieren")
    private val copyLabels = listOf("Kopieren", "Ausschneiden")

    private fun event(texts: List<CharSequence>) =
        detector.onEvent(systemUi, windowState, "android.widget.FrameLayout", texts, emptyList(), copyLabels)

    @Test
    fun onEvent_toolbarOfferedCopyThenEmptyWindow_isCopy() {
        assertFalse(event(toolbar))
        now = 1_000
        assertTrue(event(emptyList()))
    }

    @Test
    fun onEvent_emptyWindowWithoutToolbar_isNotCopy() {
        assertFalse(event(emptyList()))
    }

    @Test
    fun onEvent_emptyWindowAfterWindowExpired_isNotCopy() {
        event(toolbar)
        now = CopyDetector.DEFAULT_WINDOW_MILLIS + 1
        assertFalse(event(emptyList()))
    }

    @Test
    fun onEvent_secondEmptyWindow_isNotCopyAgain() {
        event(toolbar)
        assertTrue(event(emptyList()))
        assertFalse(event(emptyList()))
    }

    @Test
    fun onEvent_otherPackage_isNotCopy() {
        detector.onEvent("com.example", windowState, null, toolbar, emptyList(), copyLabels)
        assertFalse(detector.onEvent("com.example", windowState, null, emptyList(), emptyList(), copyLabels))
    }

    @Test
    fun onEvent_localizedOverlayLabel_isCopy() {
        assertTrue(
            detector.onEvent(systemUi, windowState, null, listOf("Kopiert"), listOf("Kopiert"), copyLabels),
        )
    }
}
