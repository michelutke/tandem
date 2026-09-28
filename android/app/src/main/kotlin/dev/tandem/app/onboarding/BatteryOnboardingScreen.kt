package dev.tandem.app.onboarding

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext

internal const val BATTERY_ONBOARDING_TITLE = "Keep Tandem connected"
internal const val BATTERY_ONBOARDING_BODY =
    "Android may stop Tandem in the background. Allow unrestricted battery use so your Mac stays connected."
internal const val BATTERY_ONBOARDING_ALLOW_LABEL = "Allow"
internal const val BATTERY_ONBOARDING_SKIP_LABEL = "Skip"

/**
 * Battery-optimization onboarding screen (E20-04, F-4.1, UC-02): shown once during onboarding
 * (skipped entirely by the caller when [BatteryOnboardingViewModel.shouldShowScreen] is false),
 * and re-accessible later from [BatteryOptimizationSettingsScreen]'s "Battery optimization" row.
 *
 * Tapping "Allow" opens the system's battery-optimization settings list
 * (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`) directly -- this isn't a seam over
 * `PowerManager`/`Build.MANUFACTURER`, so it stays inline rather than going through
 * [BatteryOptimizationSource]/[DeviceManufacturerSource]. Tapping "Skip" only invokes [onSkip];
 * no intent is launched.
 */
@Suppress("ImplicitInternalIntent") // Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS is genuinely external.
@Composable
fun BatteryOnboardingScreen(
    manufacturer: String,
    oemGuidance: OemGuidanceEntry,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    Column(modifier = modifier.fillMaxSize()) {
        Text(text = BATTERY_ONBOARDING_TITLE)
        Text(text = BATTERY_ONBOARDING_BODY)
        Button(onClick = { context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }) {
            Text(BATTERY_ONBOARDING_ALLOW_LABEL)
        }
        Button(onClick = onSkip) {
            Text(BATTERY_ONBOARDING_SKIP_LABEL)
        }
        Text(text = "Extra steps for $manufacturer")
        oemGuidance.steps.forEach { step -> Text(text = step) }
    }
}
