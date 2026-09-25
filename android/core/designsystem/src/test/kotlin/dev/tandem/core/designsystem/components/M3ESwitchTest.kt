package dev.tandem.core.designsystem.components

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E00-31 acceptance: "M3E switch: morphing thumb with check". Compose `ui:` test under
// Robolectric (tandem.android.robolectric convention).
@RunWith(AndroidJUnit4::class)
class M3ESwitchTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun m3eSwitch_toggledOn_thumbShowsCheckIcon() {
        composeRule.setContent {
            M3ESwitch(checked = true, onCheckedChange = {})
        }

        composeRule.onNodeWithTag(M3E_SWITCH_CHECK_ICON_TEST_TAG, useUnmergedTree = true).assertExists()
    }

    @Test
    fun m3eSwitch_toggledOff_thumbHasNoCheckIcon() {
        composeRule.setContent {
            M3ESwitch(checked = false, onCheckedChange = {})
        }

        composeRule.onAllNodesWithTag(M3E_SWITCH_CHECK_ICON_TEST_TAG, useUnmergedTree = true).assertCountEquals(0)
    }
}
