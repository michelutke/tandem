package dev.tandem.app

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// Compose `ui:` test running under Robolectric with no emulator (E00-20). `AndroidJUnit4`
// delegates to `RobolectricTestRunner` off-device, which is what `ActivityScenario` (used
// internally by `createComposeRule()`) expects for its instrumentation registry.
@RunWith(AndroidJUnit4::class)
class SampleComposeUiTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun composeRuleSample_buttonClicked_labelChangesToClicked() {
        composeRule.setContent { SampleButton() }

        composeRule.onNodeWithText(SAMPLE_BUTTON_INITIAL_LABEL).performClick()

        composeRule.onNodeWithText(SAMPLE_BUTTON_CLICKED_LABEL).assertExists()
    }
}
