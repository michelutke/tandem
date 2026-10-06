package dev.tandem.app.onboarding

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// E20-14 tdd:
//   unit: onboardingViewModel_api33_ordersIdentityListenerPostNotificationsBatteryScan
//   unit: onboardingViewModel_fullRunAllSkipped_requestedPermissionsExcludeLazyOnes
class OnboardingViewModelTest {
    private fun viewModel(
        batteryScreenShown: Boolean = true,
        permissionRequester: PermissionRequester = RecordingPermissionRequester(),
    ) = OnboardingViewModel(
        batteryOnboardingViewModel =
            BatteryOnboardingViewModel(
                batteryOptimizationSource =
                    FakeBatteryOptimizationSource(ignoringBatteryOptimizations = !batteryScreenShown),
                deviceManufacturerSource = FakeDeviceManufacturerSource(manufacturer = "Google"),
            ),
        permissionRequester = permissionRequester,
    )

    @Test
    fun onboardingViewModel_api33_ordersIdentityListenerPostNotificationsBatteryScan() {
        val viewModel = viewModel()

        assertEquals(
            listOf(
                OnboardingStep.IDENTITY,
                OnboardingStep.NOTIFICATION_LISTENER,
                OnboardingStep.POST_NOTIFICATIONS,
                OnboardingStep.BATTERY,
                OnboardingStep.SCAN_QR,
            ),
            viewModel.steps(),
        )
    }

    @Test
    fun onboardingViewModel_fullRunAllSkipped_requestedPermissionsExcludeLazyOnes() {
        val requester = RecordingPermissionRequester()
        val viewModel = viewModel(permissionRequester = requester)

        // A full run where every optional screen's Skip is tapped never calls
        // OnboardingViewModel.allow, so the requester never sees a call for any permission --
        // lazy features (SMS, contacts, phone, media, accessibility, notification policy) least
        // of all; OnboardingPermission itself has no case for any of them.
        viewModel.steps()

        assertTrue(requester.requested.isEmpty())
    }
}
