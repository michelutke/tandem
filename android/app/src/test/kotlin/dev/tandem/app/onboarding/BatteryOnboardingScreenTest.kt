package dev.tandem.app.onboarding

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

// E20-04 tdd:
//   ui: batteryOnboardingScreen_rendered_showsExactTitleBodyAndButtons
//   ui: batteryOnboardingScreen_allowTapped_launchesIgnoreBatteryOptimizationSettings
@RunWith(AndroidJUnit4::class)
class BatteryOnboardingScreenTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun batteryOnboardingScreen_rendered_showsExactTitleBodyAndButtons() {
        composeRule.setContent {
            BatteryOnboardingScreen(
                manufacturer = "Xiaomi",
                oemGuidance = OemGuidance.XIAOMI,
                onSkip = {},
            )
        }

        val expectedBody =
            "Android may stop Tandem in the background. Allow unrestricted battery use so your Mac stays connected."

        composeRule.onNodeWithText("Keep Tandem connected").assertExists()
        composeRule.onNodeWithText(expectedBody).assertExists()
        composeRule.onNodeWithText("Allow").assertExists()
        composeRule.onNodeWithText("Skip").assertExists()
    }

    @Test
    fun batteryOnboardingScreen_allowTapped_launchesIgnoreBatteryOptimizationSettings() {
        composeRule.setContent {
            BatteryOnboardingScreen(
                manufacturer = "Xiaomi",
                oemGuidance = OemGuidance.XIAOMI,
                onSkip = {},
            )
        }

        composeRule.onNodeWithText("Allow").performClick()

        val startedIntent = shadowOf(composeRule.activity).nextStartedActivity
        assertEquals(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS, startedIntent?.action)
    }

    @Test
    fun batteryOnboardingScreen_skipTapped_doesNotLaunchAnyIntentAndInvokesOnSkip() {
        var skipped = false
        composeRule.setContent {
            BatteryOnboardingScreen(
                manufacturer = "Xiaomi",
                oemGuidance = OemGuidance.XIAOMI,
                onSkip = { skipped = true },
            )
        }

        composeRule.onNodeWithText("Skip").performClick()

        assertEquals(true, skipped)
        assertEquals(null, shadowOf(composeRule.activity).nextStartedActivity)
    }

    @Test
    fun batteryOnboardingScreen_rendered_showsOemGuidanceSection() {
        composeRule.setContent {
            BatteryOnboardingScreen(
                manufacturer = "Xiaomi",
                oemGuidance = OemGuidance.XIAOMI,
                onSkip = {},
            )
        }

        composeRule.onNodeWithText("Extra steps for Xiaomi").assertExists()
    }
}
