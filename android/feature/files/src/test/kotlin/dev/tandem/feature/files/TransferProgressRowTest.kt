package dev.tandem.feature.files

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E40-12 tdd:
//   ui: androidProgressRow_cancelTapped_cancelFlowInvoked
@RunWith(AndroidJUnit4::class)
class TransferProgressRowTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun androidProgressRow_cancelTapped_cancelFlowInvoked() {
        var cancels = 0
        composeRule.setContent {
            TransferProgressRow(TransferProgress(percent = 42, bytesPerSecond = 1_048_576), onCancel = { cancels++ })
        }

        composeRule.onNodeWithText("42%").assertExists()
        composeRule.onNodeWithText("Cancel").performClick()

        assertEquals(1, cancels)
    }
}
