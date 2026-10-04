package dev.tandem.feature.input

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

internal const val REMOTE_INPUT_TITLE = "Control."
internal const val REMOTE_INPUT_EXPLANATION =
    "Let your Mac tap and type. Tandem asks for Accessibility so your Mac can send touches and " +
        "keys to this phone while you mirror. It stays off until you enable it, and only works " +
        "during a mirror session you start."
internal const val OPEN_ACCESSIBILITY_SETTINGS_LABEL = "Open Accessibility settings"
internal const val REMOTE_INPUT_ENABLED_LABEL = "Remote control is enabled."

/** E62-02: opt-in explanation for remote input; [accessibilityState] is the E62-02 seam. */
@Composable
fun RemoteInputSettingsScreen(
    accessibilityState: AccessibilityStateSource,
    onOpenAccessibilitySettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Text(text = REMOTE_INPUT_TITLE)
        Text(text = REMOTE_INPUT_EXPLANATION)
        if (accessibilityState.isServiceEnabled()) {
            Text(text = REMOTE_INPUT_ENABLED_LABEL)
        } else {
            Button(onClick = onOpenAccessibilitySettings) { Text(text = OPEN_ACCESSIBILITY_SETTINGS_LABEL) }
        }
    }
}
