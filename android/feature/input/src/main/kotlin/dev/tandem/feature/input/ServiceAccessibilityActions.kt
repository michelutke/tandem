package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo

class ServiceAccessibilityActions(
    private val service: AccessibilityService,
) : AccessibilityActions {
    override fun performGlobalAction(action: Int): Boolean = service.performGlobalAction(action)

    override fun findFocusedInput(): FocusedInput? {
        val node = service.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        return if (node.isEditable) NodeFocusedInput(node) else null
    }
}

private class NodeFocusedInput(
    private val node: AccessibilityNodeInfo,
) : FocusedInput {
    override val text: CharSequence? get() = node.text
    override val selectionStart: Int get() = node.textSelectionStart
    override val selectionEnd: Int get() = node.textSelectionEnd

    override fun setText(text: CharSequence): Boolean {
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    override fun setSelection(
        start: Int,
        end: Int,
    ): Boolean {
        val args =
            Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, start)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, end)
            }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, args)
    }

    override fun imeEnter(): Boolean = node.performAction(IME_ENTER_ACTION_ID)

    private companion object {
        /** AccessibilityAction.ACTION_IME_ENTER.id, API 30+. */
        const val IME_ENTER_ACTION_ID = 0x01020054
    }
}
