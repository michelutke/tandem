package dev.tandem.app.shell

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.pairing.PairingFailure
import dev.tandem.core.pairing.PairingState
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PairingScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private var matched = 0
    private var rejected = 0

    private fun show(state: PairingState) {
        composeRule.setContent {
            PairingScreen(
                state = state,
                onCodesMatch = { matched++ },
                onCodesDontMatch = { rejected++ },
                onScanAgain = {},
            )
        }
    }

    @Test
    fun pairingScreen_awaitingUserConfirm_showsGroupedCodeAndBothActions() {
        show(PairingState.AwaitingUserConfirm("482913", "MacBook Pro"))

        composeRule.onNodeWithText("482 913").assertExists()
        composeRule.onNodeWithText("Codes match").performClick()
        composeRule.onNodeWithText("They don't match").performClick()
        assertEquals(1, matched)
        assertEquals(1, rejected)
    }

    @Test
    fun pairingScreen_failed_showsErrorAndNoCodeActions() {
        show(PairingState.Failed(PairingFailure.AllAddressesUnreachable))

        composeRule.onNodeWithText("Can't reach the Mac.").assertExists()
        composeRule.onNodeWithText("Codes match").assertDoesNotExist()
    }

    @Test
    fun pairingScreen_pinMismatch_showsTrustErrorNotNetworkError() {
        show(PairingState.Failed(PairingFailure.PinMismatch))

        composeRule.onNodeWithText("Not trusted.").assertExists()
        composeRule.onNodeWithText("Can't reach the Mac.").assertDoesNotExist()
    }
}
