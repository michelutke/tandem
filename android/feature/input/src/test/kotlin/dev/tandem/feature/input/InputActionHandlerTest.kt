package dev.tandem.feature.input

import android.accessibilityservice.AccessibilityService
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.globalAction
import dev.tandem.protocol.v1.imeEnter
import dev.tandem.protocol.v1.setText
import dev.tandem.protocol.v1.textEdit
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** InputActionHandler E62-05 tests (`docs/planning/backlog/phase-6.yaml` E62-05's `tdd:` list). Plain JUnit5. */
class InputActionHandlerTest {
    private val actions = FakeAccessibilityActions()

    private fun handler(sdkInt: Int = 34) = InputActionHandler(actions, sdkInt)

    @Test
    fun globalActionHandler_eachOfBackHomeRecents_invokesMatchingConstant() {
        val expected =
            mapOf(
                GlobalActionKind.GLOBAL_ACTION_KIND_BACK to AccessibilityService.GLOBAL_ACTION_BACK,
                GlobalActionKind.GLOBAL_ACTION_KIND_HOME to AccessibilityService.GLOBAL_ACTION_HOME,
                GlobalActionKind.GLOBAL_ACTION_KIND_RECENTS to AccessibilityService.GLOBAL_ACTION_RECENTS,
            )
        expected.forEach { (kind, constant) ->
            val result = handler().handle(globalAction { action = kind })
            assertEquals(InputResult.Performed, result)
            assertEquals(constant, actions.globalActions.last())
        }
        assertEquals(3, actions.globalActions.size)
    }

    @Test
    fun globalActionHandler_unspecified_returnsNoOp() {
        val result = handler().handle(globalAction { action = GlobalActionKind.GLOBAL_ACTION_KIND_UNSPECIFIED })
        assertEquals(InputResult.NoOp, result)
        assertEquals(emptyList<Int>(), actions.globalActions)
    }

    @Test
    fun setTextHandler_focusedEditableNode_performsSetTextWithArgument() {
        val node = FakeFocusedInput("old")
        actions.focusedInput = node
        val result = handler().handle(setText { text = "hello" })
        assertEquals(InputResult.Performed, result)
        assertEquals("hello", node.text.toString())
    }

    @Test
    fun setTextHandler_noFocusedEditableNode_returnsNoOpWithoutThrowing() {
        assertEquals(InputResult.NoOp, handler().handle(setText { text = "hello" }))
    }

    @Test
    fun textEditHandler_insertAtSelection_setsTextWithInsertion() {
        val node = FakeFocusedInput("abcd", selectionStart = 1, selectionEnd = 3)
        actions.focusedInput = node
        val result = handler().handle(textEdit { insert = "XY" })
        assertEquals(InputResult.Performed, result)
        assertEquals("aXYd", node.text.toString())
        assertEquals(3 to 3, node.selectionAfterSetText)
    }

    @Test
    fun textEditHandler_deleteBackwardTwo_removesTwoCharsBeforeCursor() {
        val node = FakeFocusedInput("abcde", selectionStart = 4, selectionEnd = 4)
        actions.focusedInput = node
        val result = handler().handle(textEdit { deleteBackward = 2 })
        assertEquals(InputResult.Performed, result)
        assertEquals("abe", node.text.toString())
        assertEquals(2 to 2, node.selectionAfterSetText)
    }

    @Test
    fun textEditHandler_deleteBackwardBeyondStart_clampsAtStart() {
        val node = FakeFocusedInput("abc", selectionStart = 1, selectionEnd = 1)
        actions.focusedInput = node
        handler().handle(textEdit { deleteBackward = 5 })
        assertEquals("bc", node.text.toString())
        assertEquals(0 to 0, node.selectionAfterSetText)
    }

    @Test
    fun textEditHandler_deleteBackwardOutsideRange_returnsNoOpAndKeepsText() {
        val input = FakeFocusedInput("hello")
        actions.focusedInput = input
        listOf(0, 65, Int.MAX_VALUE).forEach { count ->
            assertEquals(InputResult.NoOp, handler().handle(textEdit { deleteBackward = count }))
        }
        assertEquals("hello", input.text.toString())
    }

    @Test
    fun textEditHandler_imeEnterOnApi29_returnsNoOp() {
        val node = FakeFocusedInput("abc")
        actions.focusedInput = node
        val result = handler(sdkInt = 29).handle(textEdit { imeEnter = imeEnter {} })
        assertEquals(InputResult.NoOp, result)
        assertEquals(0, node.imeEnterCalls)
    }

    @Test
    fun textEditHandler_imeEnterOnApi30_performsImeEnter() {
        val node = FakeFocusedInput("abc")
        actions.focusedInput = node
        val result = handler(sdkInt = 30).handle(textEdit { imeEnter = imeEnter {} })
        assertEquals(InputResult.Performed, result)
        assertEquals(1, node.imeEnterCalls)
    }

    @Test
    fun textEditHandler_noFocusedEditableNode_returnsNoOp() {
        assertEquals(InputResult.NoOp, handler().handle(textEdit { insert = "x" }))
        assertNull(actions.focusedInput)
    }

    @Test
    fun textEditHandler_unsetEdit_returnsNoOp() {
        actions.focusedInput = FakeFocusedInput("abc")
        assertEquals(InputResult.NoOp, handler().handle(textEdit {}))
    }
}
