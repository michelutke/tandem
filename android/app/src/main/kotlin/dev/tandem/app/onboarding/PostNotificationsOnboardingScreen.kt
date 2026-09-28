package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

internal const val POST_NOTIFICATIONS_ONBOARDING_TITLE = "Allow notifications"
internal const val POST_NOTIFICATIONS_ONBOARDING_BODY =
    "Tandem shows a notification while it's keeping your Mac connected, and while mirroring is active."
internal const val POST_NOTIFICATIONS_ONBOARDING_ALLOW_LABEL = "Allow"
internal const val POST_NOTIFICATIONS_ONBOARDING_SKIP_LABEL = "Skip"

/**
 * POST_NOTIFICATIONS onboarding screen (E20-14, F-4.1, UC-02, API 33+ only -- omitted below API 33
 * by [OnboardingViewModel.steps]). Tapping "Allow" invokes [onAllow] (the caller routes this
 * through [OnboardingViewModel.allow] -> [PermissionRequester], which requests the real runtime
 * permission); tapping "Skip" only invokes [onSkip] -- no permission is requested.
 */
@Composable
fun PostNotificationsOnboardingScreen(
    onAllow: () -> Unit,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        Text(text = POST_NOTIFICATIONS_ONBOARDING_TITLE)
        Text(text = POST_NOTIFICATIONS_ONBOARDING_BODY)
        Button(onClick = onAllow) {
            Text(POST_NOTIFICATIONS_ONBOARDING_ALLOW_LABEL)
        }
        Button(onClick = onSkip) {
            Text(POST_NOTIFICATIONS_ONBOARDING_SKIP_LABEL)
        }
    }
}
