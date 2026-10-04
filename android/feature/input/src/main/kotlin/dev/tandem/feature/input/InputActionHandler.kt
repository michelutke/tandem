package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import dev.tandem.protocol.v1.GlobalAction
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.SetText
import dev.tandem.protocol.v1.TextEdit

enum class InputResult { Performed, NoOp }

/**
 * Executes decoded input messages. Not reachable from transport/session code; the invariant 8
 * authorization gate (E62-06) must wrap every call. Never logs text.
 */
class InputActionHandler(
    private val actions: AccessibilityActions,
    private val sdkInt: Int,
) {
    fun handle(globalAction: GlobalAction): InputResult {
        val action =
            when (globalAction.action) {
                GlobalActionKind.GLOBAL_ACTION_KIND_BACK -> AccessibilityService.GLOBAL_ACTION_BACK
                GlobalActionKind.GLOBAL_ACTION_KIND_HOME -> AccessibilityService.GLOBAL_ACTION_HOME
                GlobalActionKind.GLOBAL_ACTION_KIND_RECENTS -> AccessibilityService.GLOBAL_ACTION_RECENTS
                else -> return InputResult.NoOp
            }
        return result(actions.performGlobalAction(action))
    }

    fun handle(setText: SetText): InputResult {
        val input = actions.findFocusedInput() ?: return InputResult.NoOp
        return result(input.setText(setText.text))
    }

    fun handle(textEdit: TextEdit): InputResult {
        val input = actions.findFocusedInput() ?: return InputResult.NoOp
        return when (textEdit.editCase) {
            TextEdit.EditCase.INSERT -> replaceSelection(input, textEdit.insert, deleteCount = 0)
            TextEdit.EditCase.DELETE_BACKWARD -> replaceSelection(input, "", textEdit.deleteBackward)
            TextEdit.EditCase.IME_ENTER -> imeEnter(input)
            else -> InputResult.NoOp
        }
    }

    private fun imeEnter(input: FocusedInput): InputResult =
        if (sdkInt >= IME_ENTER_MIN_SDK) result(input.imeEnter()) else InputResult.NoOp

    private fun replaceSelection(
        input: FocusedInput,
        insertion: String,
        deleteCount: Int,
    ): InputResult {
        val current = input.text?.toString().orEmpty()
        val start = if (input.selectionStart < 0) current.length else input.selectionStart.coerceAtMost(current.length)
        val end = if (input.selectionEnd < 0) start else input.selectionEnd.coerceIn(start, current.length)
        val removeFrom = if (start == end) (start - deleteCount).coerceAtLeast(0) else start
        val updated = current.substring(0, removeFrom) + insertion + current.substring(end)
        val cursor = removeFrom + insertion.length
        if (!input.setText(updated)) return InputResult.NoOp
        input.setSelection(cursor, cursor)
        return InputResult.Performed
    }

    private fun result(performed: Boolean) = if (performed) InputResult.Performed else InputResult.NoOp

    private companion object {
        const val IME_ENTER_MIN_SDK = 30
    }
}
