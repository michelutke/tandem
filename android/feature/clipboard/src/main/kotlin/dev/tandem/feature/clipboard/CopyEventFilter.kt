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

    /** System UI string resources whose localized values label the copy overlay. */
    val SYSTEM_UI_COPY_STRINGS =
        listOf(
            "clipboard_overlay_window_name",
            "clipboard_overlay_text_copied",
            "clipboard_text_copied",
            "clipboard_content_copied",
            "clipboard_image_copied",
        )

    /**
     * [localizedMarkers] are System UI's own strings in the device locale (e.g. "Zwischenablage",
     * "Kopiert"); the English markers stay as a fallback when they cannot be resolved.
     */
    fun isCopyOverlay(
        packageName: CharSequence?,
        eventType: Int,
        className: CharSequence?,
        texts: List<CharSequence>,
        localizedMarkers: List<String> = emptyList(),
    ): Boolean {
        val markers = localizedMarkers.filter { it.isNotBlank() } + COPIED_MARKER + CLIPBOARD_MARKER
        return packageName?.toString() == SYSTEM_UI_PACKAGE &&
            eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            (
                className.containsIgnoreCase(CLIPBOARD_MARKER) ||
                    texts.any { text -> markers.any { text.containsIgnoreCase(it) } }
            )
    }

    private fun CharSequence?.containsIgnoreCase(marker: String): Boolean =
        this?.contains(marker, ignoreCase = true) == true
}
