package dev.tandem.app.settings

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
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

    @Suppress("LongParameterList") // one callback per screen action
    private fun setScreen(
        state: SettingsState = SettingsState("MacBook Pro", batteryRestricted = false, keyShortCode = "A1B2 C3D4"),
        onFixBattery: () -> Unit = {},
        onRotateKey: () -> Unit = {},
        onUnpair: () -> Unit = {},
        onOpenPermissions: () -> Unit = {},
        onAutoCaptureChange: (Boolean) -> Unit = {},
        onOpenAccessibilitySettings: () -> Unit = {},
    ) {
        composeRule.setContent {
            SettingsScreen(
                state = state,
                onFixBattery = onFixBattery,
                onRotateKey = onRotateKey,
                onUnpair = onUnpair,
                onOpenPermissions = onOpenPermissions,
                onAutoCaptureChange = onAutoCaptureChange,
                onOpenAccessibilitySettings = onOpenAccessibilitySettings,
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
    fun settingsTab_permissionsTapped_invokesOpenPermissions() {
        var opened = 0
        setScreen(onOpenPermissions = { opened++ })

        composeRule.onNodeWithText("Review").performScrollTo().performClick()

        assertEquals(1, opened)
    }

    @Test
    fun settingsTab_autoCaptureOffByDefault_showsOff() {
        setScreen()

        composeRule.onNodeWithText(AUTO_CAPTURE_LABEL).performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Off").assertIsDisplayed()
    }

    @Test
    fun settingsTab_autoCaptureTapped_explainsThenEnablesAndOpensAccessibility() {
        val changes = mutableListOf<Boolean>()
        var accessibilityOpened = 0
        setScreen(onAutoCaptureChange = { changes += it }, onOpenAccessibilitySettings = { accessibilityOpened++ })

        composeRule.onNodeWithText(AUTO_CAPTURE_LABEL).performScrollTo().performClick()
        assertEquals(emptyList<Boolean>(), changes)
        composeRule.onNodeWithText(AUTO_CAPTURE_EXPLANATION).assertIsDisplayed()
        composeRule.onNodeWithText("Open Accessibility").performClick()

        assertEquals(listOf(true), changes)
        assertEquals(1, accessibilityOpened)
    }

    @Test
    fun settingsTab_autoCaptureOnButServiceOff_tapOpensAccessibility() {
        var accessibilityOpened = 0
        setScreen(
            state =
                SettingsState(
                    "MacBook Pro",
                    batteryRestricted = false,
                    keyShortCode = "A1B2 C3D4",
                    autoCapture = true,
                ),
            onOpenAccessibilitySettings = { accessibilityOpened++ },
        )

        composeRule.onNodeWithText("Allow Tandem in Accessibility settings.").performScrollTo().performClick()

        assertEquals(1, accessibilityOpened)
    }

    @Test
    fun settingsTab_autoCaptureOffButServiceStillOn_showsRemoveAccessHintWithLink() {
        var accessibilityOpened = 0
        setScreen(
            state =
                SettingsState(
                    "MacBook Pro",
                    batteryRestricted = false,
                    keyShortCode = "A1B2 C3D4",
                    autoCaptureServiceOn = true,
                ),
            onOpenAccessibilitySettings = { accessibilityOpened++ },
        )

        composeRule.onNodeWithText(AUTO_CAPTURE_REMOVE_ACCESS_HINT).performScrollTo().performClick()

        assertEquals(1, accessibilityOpened)
    }

    @Test
    fun settingsTab_autoCaptureOffServiceOff_hidesRemoveAccessHint() {
        setScreen()

        composeRule.onNodeWithText(AUTO_CAPTURE_REMOVE_ACCESS_HINT).assertDoesNotExist()
    }

    @Test
    fun settingsTab_autoCaptureOn_tapTurnsOff() {
        val changes = mutableListOf<Boolean>()
        setScreen(
            state =
                SettingsState(
                    "MacBook Pro",
                    batteryRestricted = false,
                    keyShortCode = "A1B2 C3D4",
                    autoCapture = true,
                    autoCaptureServiceOn = true,
                ),
            onAutoCaptureChange = { changes += it },
        )

        composeRule.onNodeWithText(AUTO_CAPTURE_LABEL).performScrollTo().performClick()

        assertEquals(listOf(false), changes)
    }

    @Test
    fun settingsTab_unpairConfirmed_invokesUnpairAction() {
        var unpaired = 0
        setScreen(onUnpair = { unpaired++ })

        composeRule.onNodeWithText("Unpair").performScrollTo().performClick()
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

        composeRule.onNodeWithText("Unpair").performScrollTo().performClick()
        composeRule.onNodeWithText("Cancel").performClick()

        assertEquals(0, unpaired)
        composeRule.onNodeWithText("Unpair MacBook Pro?").assertDoesNotExist()
    }
}
