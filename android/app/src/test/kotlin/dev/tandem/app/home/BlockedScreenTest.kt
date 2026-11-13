package dev.tandem.app.home

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// Invariant 5: a trust failure replaces Home with a visible error and offers only Pair again / Unpair.
@RunWith(AndroidJUnit4::class)
class BlockedScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private fun show(
        reason: BlockedReason,
        onPairAgain: () -> Unit = {},
        onUnpair: () -> Unit = {},
    ) = composeRule.setContent {
        BlockedScreen(reason = reason, macName = "MacBook Pro", onPairAgain = onPairAgain, onUnpair = onUnpair)
    }

    @Test
    fun blockedScreen_pinMismatch_showsKeyChangedAndBothActions() {
        var pairAgain = 0
        var unpair = 0
        show(BlockedReason.PinMismatch, { pairAgain++ }, { unpair++ })

        composeRule.onNodeWithText("Blocked.", substring = true).assertExists()
        composeRule.onNodeWithText("The Mac's key changed.", substring = true).assertExists()
        composeRule.onNodeWithText("Pair again").performClick()
        composeRule.onNodeWithText("Unpair").performClick()
        assertEquals(1, pairAgain)
        assertEquals(1, unpair)
    }

    @Test
    fun blockedScreen_revoked_namesTheMac() {
        show(BlockedReason.Revoked)

        composeRule.onNodeWithText("MacBook Pro removed this phone.", substring = true).assertExists()
        composeRule.onNodeWithText("Pair again").assertExists()
    }

    @Test
    fun blockedScreen_revokedWithoutMacName_usesFallbackFromResources() {
        composeRule.setContent {
            BlockedScreen(reason = BlockedReason.Revoked, macName = null, onPairAgain = {}, onUnpair = {})
        }

        composeRule.onNodeWithText("The Mac removed this phone.", substring = true).assertExists()
    }

    @Test
    fun blockedScreen_updateNeeded_offersOnlyUnpair() {
        show(BlockedReason.UpdateNeeded)

        composeRule.onNodeWithText("Update needed.", substring = true).assertExists()
        composeRule.onNodeWithText("Pair again").assertDoesNotExist()
        composeRule.onNodeWithText("Unpair").assertExists()
    }
}
