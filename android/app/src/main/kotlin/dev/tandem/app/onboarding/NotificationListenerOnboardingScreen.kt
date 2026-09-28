package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

internal const val NOTIFICATION_LISTENER_ONBOARDING_TITLE = "Mirror notifications"
internal const val NOTIFICATION_LISTENER_ONBOARDING_BODY =
    "Tandem reads notifications on this phone so it can mirror them to your Mac. " +
        "Notification content stays on-device unless you mirror it."
internal const val NOTIFICATION_LISTENER_ONBOARDING_ALLOW_LABEL = "Allow"
internal const val NOTIFICATION_LISTENER_ONBOARDING_SKIP_LABEL = "Skip"

/**
 * Notification-listener access onboarding screen (E20-14, F-4.1, UC-02): explains why Tandem
 * needs notification-listener access before sending the user to the system's dedicated Settings
 * screen -- there is no runtime-permission dialog for this special access. Tapping "Allow" invokes
 * [onAllow] (the caller routes this through [OnboardingViewModel.allow] -> [PermissionRequester]);
 * tapping "Skip" only invokes [onSkip] -- no settings screen is opened.
 */
@Composable
fun NotificationListenerOnboardingScreen(
    onAllow: () -> Unit,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        Text(text = NOTIFICATION_LISTENER_ONBOARDING_TITLE)
        Text(text = NOTIFICATION_LISTENER_ONBOARDING_BODY)
        Button(onClick = onAllow) {
            Text(NOTIFICATION_LISTENER_ONBOARDING_ALLOW_LABEL)
        }
        Button(onClick = onSkip) {
            Text(NOTIFICATION_LISTENER_ONBOARDING_SKIP_LABEL)
        }
    }
}
