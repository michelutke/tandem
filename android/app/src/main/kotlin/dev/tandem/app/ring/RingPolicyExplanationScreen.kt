package dev.tandem.app.ring

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext

internal const val RING_POLICY_EXPLANATION_TEXT =
    "To ring even when Do Not Disturb is on, Tandem needs Do Not Disturb access. " +
        "It is only used while your Mac is ringing this phone."
internal const val RING_POLICY_EXPLANATION_BUTTON_LABEL = "Open settings"

/**
 * Do Not Disturb access explanation screen (E23-05, F-4.4, UC-06): shown when
 * [RingHandler.needsPolicyExplanation] is true, before the user can open the system's
 * notification policy access settings.
 */
@Suppress("ImplicitInternalIntent") // Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS is genuinely external.
@Composable
fun RingPolicyExplanationScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current

    Column(modifier = modifier.fillMaxSize()) {
        Text(text = RING_POLICY_EXPLANATION_TEXT)
        Button(onClick = { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) }) {
            Text(RING_POLICY_EXPLANATION_BUTTON_LABEL)
        }
    }
}
