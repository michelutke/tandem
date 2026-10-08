package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent

/**
 * Copy detection on top of [CopyEventFilter] (ADR-007). On Pixel builds the System UI copy overlay
 * arrives as a plain `FrameLayout` window-state event carrying at most one text (the clip preview,
 * or nothing), whether the copy came from the selection toolbar or an app's own copy button. Other
 * System UI windows differ: the volume panel has its own class, the notification shade and the
 * selection toolbar carry several texts, and the toolbar lists the Copy/Cut labels. A spurious
 * match only re-reads an unchanged clip, which the capture activity skips.
 */
object CopyDetector {
    private const val FRAME_LAYOUT = "android.widget.FrameLayout"

    @Suppress("LongParameterList") // mirrors the AccessibilityEvent fields the filter inspects
    fun isCopy(
        packageName: CharSequence?,
        eventType: Int,
        className: CharSequence?,
        texts: List<CharSequence>,
        localizedMarkers: List<String>,
        copyActionLabels: List<String>,
    ): Boolean {
        if (CopyEventFilter.isCopyOverlay(packageName, eventType, className, texts, localizedMarkers)) return true
        val isSystemUiWindow =
            packageName?.toString() == CopyEventFilter.SYSTEM_UI_PACKAGE &&
                eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        val offersCopy = texts.any { text -> copyActionLabels.any { text.toString().equals(it, ignoreCase = true) } }
        return isSystemUiWindow && className?.toString() == FRAME_LAYOUT && texts.size <= 1 && !offersCopy
    }
}
