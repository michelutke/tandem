package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** ADR-007 copy detection from the System UI event shapes seen on a Pixel (Android 16). Plain JUnit5. */
class CopyDetectorTest {
    private val systemUi = "com.android.systemui"
    private val windowState = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
    private val frame = "android.widget.FrameLayout"
    private val copyLabels = listOf("Kopieren", "Ausschneiden")

    private fun isCopy(
        texts: List<CharSequence>,
        className: String = frame,
        packageName: String = systemUi,
    ) = CopyDetector.isCopy(packageName, windowState, className, texts, emptyList(), copyLabels)

    @Test
    fun isCopy_overlayWithPreviewText_isCopy() {
        assertTrue(isCopy(listOf("x".repeat(112))))
    }

    @Test
    fun isCopy_overlayWithoutText_isCopy() {
        assertTrue(isCopy(emptyList()))
    }

    @Test
    fun isCopy_selectionToolbar_isNotCopy() {
        assertFalse(isCopy(listOf("Weitere Optionen", "Übersetzen", "Ausschneiden", "Kopieren")))
    }

    @Test
    fun isCopy_singleCopyActionLabel_isNotCopy() {
        assertFalse(isCopy(listOf("Kopieren")))
    }

    @Test
    fun isCopy_notificationShade_isNotCopy() {
        assertFalse(isCopy(listOf("a".repeat(22), "b".repeat(5), "c".repeat(5))))
    }

    @Test
    fun isCopy_volumeDialog_isNotCopy() {
        assertFalse(isCopy(listOf("d".repeat(16)), className = "com.android.systemui.volume.dialog.VolumeDialog"))
    }

    @Test
    fun isCopy_otherPackage_isNotCopy() {
        assertFalse(isCopy(emptyList(), packageName = "com.example"))
    }

    @Test
    fun isCopy_localizedOverlayLabel_isCopy() {
        assertTrue(
            CopyDetector.isCopy(systemUi, windowState, null, listOf("Kopiert"), listOf("Kopiert"), copyLabels),
        )
    }
}
