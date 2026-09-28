package dev.tandem.app.onboarding

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E20-04 tdd: ui: settingsScreen_batteryOptimizationRowTapped_showsOemGuidanceSection
@RunWith(AndroidJUnit4::class)
class BatteryOptimizationSettingsScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun settingsScreen_rendered_showsBatteryOptimizationRow() {
        composeRule.setContent {
            BatteryOptimizationSettingsScreen(manufacturer = "Xiaomi", oemGuidance = OemGuidance.XIAOMI)
        }

        composeRule.onNodeWithText("Battery optimization").assertExists()
    }

    @Test
    fun settingsScreen_batteryOptimizationRowTapped_showsOemGuidanceSection() {
        composeRule.setContent {
            BatteryOptimizationSettingsScreen(manufacturer = "Xiaomi", oemGuidance = OemGuidance.XIAOMI)
        }

        composeRule.onNodeWithText("Battery optimization").performClick()

        composeRule.onNodeWithText("Extra steps for Xiaomi").assertExists()
        composeRule.onNodeWithText("Keep Tandem connected").assertExists()
    }
}
