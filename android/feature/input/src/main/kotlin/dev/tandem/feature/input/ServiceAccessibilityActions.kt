package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
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

    override fun dispatchGesture(stroke: GestureStroke): Boolean {
        val path =
            Path().apply {
                moveTo(stroke.startX, stroke.startY)
                if (stroke.endX != stroke.startX || stroke.endY != stroke.startY) lineTo(stroke.endX, stroke.endY)
            }
        val gesture =
            GestureDescription
                .Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0L, stroke.durationMs))
                .build()
        return service.dispatchGesture(gesture, null, null)
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

    override fun imeEnter(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
}
