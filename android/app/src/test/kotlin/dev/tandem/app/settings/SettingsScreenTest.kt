package dev.tandem.app.settings

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.designsystem.components.FloatingToolbarItem
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E20-19 tdd:
//   ui: settingsTab_batteryRestricted_showsFixAction
//   ui: settingsTab_unpairConfirmed_invokesUnpairAction
@RunWith(AndroidJUnit4::class)
class SettingsScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun setScreen(
        state: SettingsState = SettingsState("MacBook Pro", batteryRestricted = false, keyShortCode = "A1B2 C3D4"),
        onFixBattery: () -> Unit = {},
        onRotateKey: () -> Unit = {},
        onUnpair: () -> Unit = {},
    ) {
        composeRule.setContent {
            SettingsScreen(
                state = state,
                selectedToolbarItem = FloatingToolbarItem.Settings,
                onToolbarItemSelected = {},
                onFixBattery = onFixBattery,
                onRotateKey = onRotateKey,
                onUnpair = onUnpair,
            )
        }
    }

    @Test
    fun settingsTab_showsPairedMacAndKeyShortCode() {
        setScreen()

        composeRule.onNodeWithText("MacBook Pro").assertIsDisplayed()
        composeRule.onNodeWithText("A1B2 C3D4").assertIsDisplayed()
    }

    @Test
    fun settingsTab_batteryUnrestricted_hidesFixAction() {
        setScreen()

        composeRule.onNodeWithText("Fix").assertDoesNotExist()
    }

    @Test
    fun settingsTab_batteryRestricted_showsFixAction() {
        var fixed = 0
        setScreen(
            state = SettingsState(macName = "MacBook Pro", batteryRestricted = true, keyShortCode = "A1B2 C3D4"),
            onFixBattery = { fixed++ },
        )

        composeRule.onNodeWithText("Restricted").assertIsDisplayed()
        composeRule.onNodeWithText("Fix").assertIsDisplayed().performClick()

        assertEquals(1, fixed)
    }

    @Test
    fun settingsTab_rotateTapped_invokesRotateKey() {
        var rotated = 0
        setScreen(onRotateKey = { rotated++ })

        composeRule.onNodeWithText("Rotate").performClick()

        assertEquals(1, rotated)
    }

    @Test
    fun settingsTab_unpairConfirmed_invokesUnpairAction() {
        var unpaired = 0
        setScreen(onUnpair = { unpaired++ })

        composeRule.onNodeWithText("Unpair").performClick()
        assertEquals(0, unpaired)
        composeRule.onNodeWithText("Unpair MacBook Pro?").assertIsDisplayed()
        composeRule.onAllNodesWithText("Unpair").onLast().performClick()

        assertEquals(1, unpaired)
        composeRule.onNodeWithText("Unpair MacBook Pro?").assertDoesNotExist()
    }

    @Test
    fun settingsTab_unpairCancelled_doesNotInvokeUnpairAction() {
        var unpaired = 0
        setScreen(onUnpair = { unpaired++ })

        composeRule.onNodeWithText("Unpair").performClick()
        composeRule.onNodeWithText("Cancel").performClick()

        assertEquals(0, unpaired)
        composeRule.onNodeWithText("Unpair MacBook Pro?").assertDoesNotExist()
    }
}
