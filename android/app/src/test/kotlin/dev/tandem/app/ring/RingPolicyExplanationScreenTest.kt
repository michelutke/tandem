package dev.tandem.app.ring

import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E23-05 tdd: ui: ringPolicyExplanationScreen_rendered_showsExactExplanationText
@RunWith(AndroidJUnit4::class)
class RingPolicyExplanationScreenTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun ringPolicyExplanationScreen_rendered_showsExactExplanationText() {
        composeRule.setContent {
            RingPolicyExplanationScreen()
        }

        val expectedText =
            "To ring even when Do Not Disturb is on, Tandem needs Do Not Disturb access. " +
                "It is only used while your Mac is ringing this phone."

        composeRule.onNodeWithText(expectedText).assertExists()
        composeRule.onNodeWithText("Open settings").assertExists()
    }

    @Test
    fun ringPolicyExplanationScreen_openSettingsTapped_launchesNotificationPolicyAccessSettings() {
        composeRule.setContent {
            RingPolicyExplanationScreen()
        }

        composeRule.onNodeWithText("Open settings").performClick()

        val startedIntent = shadowOf(composeRule.activity).nextStartedActivity
        assertEquals(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS, startedIntent?.action)
    }
}
