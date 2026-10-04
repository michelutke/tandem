package dev.tandem.feature.input

/** Framework seam over AccessibilityService; the real implementation is [ServiceAccessibilityActions]. */
interface AccessibilityActions {
    fun performGlobalAction(action: Int): Boolean

    /** The input-focused editable node, or null when none. */
    fun findFocusedInput(): FocusedInput?
}

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
