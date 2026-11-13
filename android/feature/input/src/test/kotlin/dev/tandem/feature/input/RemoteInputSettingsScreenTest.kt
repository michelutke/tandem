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

    private fun show(
        enabled: Boolean,
        onOpen: () -> Unit = {},
        onViewOnly: () -> Unit = {},
    ) = composeRule.setContent {
        RemoteInputSettingsScreen(
            accessibilityState = FakeAccessibilityStateSource(enabled = enabled),
            onOpenAccessibilitySettings = onOpen,
            onViewOnly = onViewOnly,
        )
    }

    @Test
    fun remoteInputSettings_serviceNotEnabled_showsThreeFactsAndOpenSettingsAction() {
        var openSettingsTaps = 0
        show(enabled = false, onOpen = { openSettingsTaps++ })

        composeRule.onNodeWithText("Control.").assertExists()
        composeRule.onNodeWithText("Let your Mac tap and type.").assertExists()
        composeRule.onNodeWithText("Uses Android Accessibility, only while mirroring").assertExists()
        composeRule.onNodeWithText("A pill on screen shows when the Mac is in control").assertExists()
        composeRule.onNodeWithText("Turn off any time in Settings").assertExists()
        composeRule.onNodeWithText("Open Accessibility settings").assertExists().performClick()
        assertEquals(1, openSettingsTaps)
    }

    @Test
    fun remoteInputSettings_serviceEnabled_hidesOpenSettingsAction() {
        show(enabled = true)

        composeRule.onNodeWithText("Open Accessibility settings").assertDoesNotExist()
        composeRule.onNodeWithText("Remote control is enabled.").assertExists()
    }

    @Test
    fun remoteInputSettings_viewOnlyTapped_callsViewOnly() {
        var viewOnlyTaps = 0
        show(enabled = false, onViewOnly = { viewOnlyTaps++ })

        composeRule.onNodeWithText("View only").performClick()

        assertEquals(1, viewOnlyTaps)
    }
}
