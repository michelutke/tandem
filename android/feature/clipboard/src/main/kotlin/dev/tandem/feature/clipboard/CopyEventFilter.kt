package dev.tandem.feature.clipboard

import android.view.accessibility.AccessibilityEvent

/**
 * Recognises the system clipboard overlay that Android 13+ shows after a copy (ADR-007). Only the
 * event's package, type, class name and text are inspected, never any other app's content; the
 * service config already restricts events to [SYSTEM_UI_PACKAGE] and window-state changes.
 */
object CopyEventFilter {
    const val SYSTEM_UI_PACKAGE = "com.android.systemui"
    private const val CLIPBOARD_MARKER = "clipboard"
    private const val COPIED_MARKER = "copied"

    fun isCopyOverlay(
        packageName: CharSequence?,
        eventType: Int,
        className: CharSequence?,
        texts: List<CharSequence>,
    ): Boolean =
        packageName?.toString() == SYSTEM_UI_PACKAGE &&
            eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            (
                className.containsIgnoreCase(CLIPBOARD_MARKER) ||
                    texts.any { it.containsIgnoreCase(COPIED_MARKER) }
            )

    private fun CharSequence?.containsIgnoreCase(marker: String): Boolean =
        this?.contains(marker, ignoreCase = true) == true
}
