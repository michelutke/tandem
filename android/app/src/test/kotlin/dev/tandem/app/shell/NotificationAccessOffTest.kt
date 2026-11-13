package dev.tandem.app.shell

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NotificationAccessOffTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun notificationAccessOff_shown_showsStateExplanationAndAllowAccess() {
        var allowTaps = 0
        composeRule.setContent { NotificationAccessOff(onAllowAccess = { allowTaps++ }) }

        composeRule.onNodeWithText("Notifications.", substring = true).assertExists()
        composeRule.onNodeWithText("Access off.", substring = true).assertExists()
        composeRule
            .onNodeWithText(
                "Android turned off notification access for Tandem. Nothing is forwarded until you allow it again.",
            ).assertExists()
        composeRule.onNodeWithText("Allow access").performClick()
        assertEquals(1, allowTaps)
    }
}
