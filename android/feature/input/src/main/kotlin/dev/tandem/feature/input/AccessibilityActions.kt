package dev.tandem.feature.input

/** Framework seam over AccessibilityService; the real implementation is [ServiceAccessibilityActions]. */
interface AccessibilityActions {
    fun performGlobalAction(action: Int): Boolean

    /** The input-focused editable node, or null when none. */
    fun findFocusedInput(): FocusedInput?

    /** Dispatches one stroke in device pixels; a stroke whose start equals its end is a single-point tap. */
    fun dispatchGesture(stroke: GestureStroke): Boolean
}

data class GestureStroke(
    val startX: Float,
    val startY: Float,
    val endX: Float,
    val endY: Float,
    val durationMs: Long,
)

interface FocusedInput {
    val text: CharSequence?
    val selectionStart: Int
    val selectionEnd: Int

    fun setText(text: CharSequence): Boolean

    fun setSelection(
        start: Int,
        end: Int,
    ): Boolean

    fun imeEnter(): Boolean
}
