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
 * Hosts the onboarding sequence (E20-14, F-4.1, F-1.1, UC-02): renders [viewModel]'s current
 * [OnboardingStep] and advances on "Allow"/"Skip". [OnboardingStep.IDENTITY] has no screen of its
 * own -- identity bootstrap runs silently before this host is shown (E10-04) -- so it is skipped
 * over here. The caller supplies [onScanAccepted]/[onCancelScan] for the reused
 * [OnboardingScanScreen]; [viewModel]'s own [OnboardingViewModel.batteryManufacturer] /
 * [OnboardingViewModel.batteryOemGuidance] feed the reused [BatteryOnboardingScreen].
 */
@Composable
fun OnboardingScreen(
    viewModel: OnboardingViewModel,
    onScanAccepted: (PairingInvite) -> Unit,
    onCancelScan: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val screenSteps = remember { viewModel.steps().filterNot { it == OnboardingStep.IDENTITY } }
    var stepIndex by remember { mutableIntStateOf(0) }

    when (screenSteps.getOrElse(stepIndex) { OnboardingStep.SCAN_QR }) {
        OnboardingStep.NOTIFICATION_LISTENER -> {
            NotificationListenerOnboardingScreen(
                onAllow = {
                    viewModel.allow(OnboardingStep.NOTIFICATION_LISTENER)
                    stepIndex++
                },
                onSkip = { stepIndex++ },
                modifier = modifier.fillMaxSize(),
            )
        }

        OnboardingStep.POST_NOTIFICATIONS -> {
            PostNotificationsOnboardingScreen(
                onAllow = {
                    viewModel.allow(OnboardingStep.POST_NOTIFICATIONS)
                    stepIndex++
                },
                onSkip = { stepIndex++ },
                modifier = modifier.fillMaxSize(),
            )
        }

        OnboardingStep.BATTERY -> {
            BatteryOnboardingScreen(
                manufacturer = viewModel.batteryManufacturer(),
                oemGuidance = viewModel.batteryOemGuidance(),
                onSkip = { stepIndex++ },
                modifier = modifier.fillMaxSize(),
            )
        }

        OnboardingStep.SCAN_QR, OnboardingStep.IDENTITY -> {
            OnboardingScanScreen(
                onScanAccepted = onScanAccepted,
                onCancel = onCancelScan,
                modifier = modifier.fillMaxSize(),
            )
        }
    }
}
