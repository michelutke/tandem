package dev.tandem.app.onboarding

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Onboarding order per ui-spec §7.2: welcome, permissions, scan.
class OnboardingViewModelTest {
    private val requester = RecordingPermissionRequester()
    private val checker = FakePermissionChecker()
    private val viewModel = OnboardingViewModel(requester, checker)

    @Test
    fun onboardingViewModel_steps_ordersIdentityWelcomePermissionsScan() {
        assertEquals(
            listOf(
                OnboardingStep.IDENTITY,
                OnboardingStep.WELCOME,
                OnboardingStep.PERMISSIONS,
                OnboardingStep.SCAN_QR,
            ),
            viewModel.steps(),
        )
    }

    @Test
    fun onboardingViewModel_rows_matchUiSpecOrder() {
        assertEquals(
            listOf(
                PermissionRow.NOTIFICATIONS,
                PermissionRow.BATTERY,
                PermissionRow.CAMERA,
                PermissionRow.SMS_AND_CALLS,
                PermissionRow.LOCAL_NETWORK,
            ),
            viewModel.rows(),
        )
    }

    @Test
    fun onboardingViewModel_allowNotifications_requestsPostNotificationsThenListener() {
        viewModel.allow(PermissionRow.NOTIFICATIONS)
        checker.granted += OnboardingPermission.POST_NOTIFICATIONS
        viewModel.allow(PermissionRow.NOTIFICATIONS)

        assertEquals(
            listOf(OnboardingPermission.POST_NOTIFICATIONS, OnboardingPermission.NOTIFICATION_LISTENER),
            requester.requested,
        )
    }

    @Test
    fun onboardingViewModel_notificationsRowPartiallyGranted_notGranted() {
        checker.granted += OnboardingPermission.POST_NOTIFICATIONS

        assertFalse(viewModel.isGranted(PermissionRow.NOTIFICATIONS))
    }

    @Test
    fun onboardingViewModel_allowGrantedRow_requestsNothing() {
        checker.granted += OnboardingPermission.CAMERA

        viewModel.allow(PermissionRow.CAMERA)

        assertTrue(requester.requested.isEmpty())
        assertTrue(viewModel.isGranted(PermissionRow.CAMERA))
    }
}
