package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import dev.tandem.core.pairing.qr.PairingInvite

/**
 * Hosts the onboarding sequence (F-4.1, F-1.1, UC-02): welcome, permissions, then the reused
 * [OnboardingScanScreen]. [OnboardingStep.IDENTITY] has no screen of its own -- identity bootstrap
 * runs silently before this host is shown (E10-04) -- so it is skipped over here.
 */
@Composable
fun OnboardingScreen(
    viewModel: OnboardingViewModel,
    onScanAccepted: (PairingInvite) -> Unit,
    onCancelScan: () -> Unit,
    modifier: Modifier = Modifier,
    onPairWithoutCamera: (() -> Unit)? = null,
) {
    val screenSteps = remember { viewModel.steps().filterNot { it == OnboardingStep.IDENTITY } }
    var stepIndex by remember { mutableIntStateOf(0) }

    when (screenSteps.getOrElse(stepIndex) { OnboardingStep.SCAN_QR }) {
        OnboardingStep.WELCOME -> {
            WelcomeScreen(onGetStarted = { stepIndex++ }, modifier = modifier.fillMaxSize())
        }

        OnboardingStep.PERMISSIONS -> {
            PermissionsScreen(viewModel = viewModel, onDone = { stepIndex++ }, modifier = modifier.fillMaxSize())
        }

        OnboardingStep.SCAN_QR, OnboardingStep.IDENTITY -> {
            OnboardingScanScreen(
                onScanAccepted = onScanAccepted,
                onCancel = onCancelScan,
                modifier = modifier.fillMaxSize(),
                onPairWithoutCamera = onPairWithoutCamera,
            )
        }
    }
}
