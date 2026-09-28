package dev.tandem.app.onboarding

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext

internal const val DISABLED_FEATURE_ROW_LABEL = "Disabled, tap to enable"

/**
 * A feature row (E20-14 acceptance criterion 4) for a permission that was skipped or denied
 * during onboarding: shows [DISABLED_FEATURE_ROW_LABEL] under [featureName] and, on tap,
 * deep-links to that feature's system Settings screen. [settingsIntentAction] is an
 * `android.provider.Settings` action string (e.g. `ACTION_NOTIFICATION_LISTENER_SETTINGS`)
 * matching the feature named by [featureName].
 */
@Suppress("ImplicitInternalIntent") // the Settings actions this row launches are genuinely external.
@Composable
fun DisabledFeatureRow(
    featureName: String,
    settingsIntentAction: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    Column(modifier = modifier.fillMaxSize()) {
        Text(text = featureName)
        Text(
            text = DISABLED_FEATURE_ROW_LABEL,
            modifier = Modifier.clickable { context.startActivity(Intent(settingsIntentAction)) },
        )
    }
}
