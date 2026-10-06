package dev.tandem.app.onboarding

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E20-14 tdd: ui: onboardingOptionalScreens_skipTapped_advancesToNextScreen
@RunWith(AndroidJUnit4::class)
class OnboardingScreenTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun onboardingOptionalScreens_skipTapped_advancesToNextScreen() {
        val viewModel =
            OnboardingViewModel(
                batteryOnboardingViewModel =
                    BatteryOnboardingViewModel(
                        batteryOptimizationSource = FakeBatteryOptimizationSource(ignoringBatteryOptimizations = false),
                        deviceManufacturerSource = FakeDeviceManufacturerSource(manufacturer = "Xiaomi"),
                    ),
                permissionRequester = RecordingPermissionRequester(),
            )

        composeRule.setContent {
            OnboardingScreen(
                viewModel = viewModel,
                onScanAccepted = {},
                onCancelScan = {},
            )
        }

        composeRule.onNodeWithText(NOTIFICATION_LISTENER_ONBOARDING_TITLE).assertExists()
        composeRule.onNodeWithText("Skip").performClick()

        composeRule.onNodeWithText(POST_NOTIFICATIONS_ONBOARDING_TITLE).assertExists()
        composeRule.onNodeWithText("Skip").performClick()

        composeRule.onNodeWithText(BATTERY_ONBOARDING_TITLE).assertExists()
        composeRule.onNodeWithText("Skip").performClick()

        composeRule.onNodeWithText(ONBOARDING_SCAN_TITLE).assertExists()
        composeRule.onNodeWithText("Skip").assertDoesNotExist()
    }
}
