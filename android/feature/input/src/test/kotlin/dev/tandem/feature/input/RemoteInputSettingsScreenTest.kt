package dev.tandem.feature.input

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E62-02 tdd: ui: remoteInputSettings_serviceNotEnabled_showsExplanationAndOpenSettingsAction
// Compose `ui:` test under Robolectric (E00-20).
@RunWith(AndroidJUnit4::class)
class RemoteInputSettingsScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun remoteInputSettings_serviceNotEnabled_showsExplanationAndOpenSettingsAction() {
        var openSettingsTaps = 0

        composeRule.setContent {
            RemoteInputSettingsScreen(
                accessibilityState = FakeAccessibilityStateSource(enabled = false),
                onOpenAccessibilitySettings = { openSettingsTaps++ },
            )
        }

        composeRule.onNodeWithText(REMOTE_INPUT_EXPLANATION).assertExists()
        composeRule.onNodeWithText(OPEN_ACCESSIBILITY_SETTINGS_LABEL).assertExists().performClick()
        assertEquals(1, openSettingsTaps)
    }

    @Test
    fun remoteInputSettings_serviceEnabled_hidesOpenSettingsAction() {
        composeRule.setContent {
            RemoteInputSettingsScreen(
                accessibilityState = FakeAccessibilityStateSource(enabled = true),
                onOpenAccessibilitySettings = {},
            )
        }

        composeRule.onNodeWithText(OPEN_ACCESSIBILITY_SETTINGS_LABEL).assertDoesNotExist()
    }
}
