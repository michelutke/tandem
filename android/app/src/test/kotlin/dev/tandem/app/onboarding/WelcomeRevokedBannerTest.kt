package dev.tandem.app.onboarding

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WelcomeRevokedBannerTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun welcomeScreen_revokedByMac_showsBannerAndDismissCallsBack() {
        var dismissed = 0
        composeRule.setContent {
            WelcomeScreen(onGetStarted = {}, revokedBy = "MacBook Pro", onDismissRevoked = { dismissed++ })
        }

        composeRule.onNodeWithText("MacBook Pro removed this phone.").assertExists()
        composeRule.onNodeWithText("Dismiss").performClick()
        assertEquals(1, dismissed)
    }

    @Test
    fun welcomeScreen_notRevoked_showsNoBanner() {
        composeRule.setContent { WelcomeScreen(onGetStarted = {}) }

        composeRule.onNodeWithText("Dismiss").assertDoesNotExist()
    }
}
