package dev.tandem.feature.input

class FakeFocusedInput(
    override var text: CharSequence = "",
    override var selectionStart: Int = text.length,
    override var selectionEnd: Int = text.length,
) : FocusedInput {
    var selectionAfterSetText: Pair<Int, Int>? = null
    var imeEnterCalls = 0

    override fun setText(text: CharSequence): Boolean {
        this.text = text
        return true
    }

    override fun setSelection(
        start: Int,
        end: Int,
    ): Boolean {
        selectionAfterSetText = start to end
        return true
    }

    override fun imeEnter(): Boolean {
        imeEnterCalls++
        return true
    }
}

class FakeAccessibilityActions(
    var focusedInput: FocusedInput? = null,
) : AccessibilityActions {
    val globalActions = mutableListOf<Int>()
    val strokes = mutableListOf<GestureStroke>()

    override fun performGlobalAction(action: Int): Boolean {
        globalActions += action
        return true
    }

    override fun findFocusedInput(): FocusedInput? = focusedInput

    override fun dispatchGesture(stroke: GestureStroke): Boolean {
        strokes += stroke
        return true
    }
}
