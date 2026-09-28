package dev.tandem.app.onboarding

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

internal const val BATTERY_OPTIMIZATION_SETTINGS_ROW_LABEL = "Battery optimization"

/**
 * The settings-tab row (E20-19) that reopens the battery onboarding screen (E20-04): tapping
 * "Battery optimization" shows the same [BatteryOnboardingScreen], OEM section included, so the
 * user can redo the OEM steps or grant the exemption after skipping it during onboarding. E20-19
 * hosts this row inside the full settings tab; this composable only owns the row-tap ->
 * screen-reopen behavior this issue's acceptance criteria require.
 */
@Composable
fun BatteryOptimizationSettingsScreen(
    manufacturer: String,
    oemGuidance: OemGuidanceEntry,
    modifier: Modifier = Modifier,
) {
    var showBatteryOnboarding by remember { mutableStateOf(false) }

    if (showBatteryOnboarding) {
        BatteryOnboardingScreen(
            manufacturer = manufacturer,
            oemGuidance = oemGuidance,
            onSkip = { showBatteryOnboarding = false },
            modifier = modifier,
        )
    } else {
        Column(modifier = modifier.fillMaxSize()) {
            Text(
                text = BATTERY_OPTIMIZATION_SETTINGS_ROW_LABEL,
                modifier = Modifier.clickable { showBatteryOnboarding = true },
            )
        }
    }
}
