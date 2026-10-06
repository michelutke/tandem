package dev.tandem.app.onboarding

/**
 * View model for the onboarding sequence (E20-14, F-4.1, F-1.1, UC-02): identity bootstrap,
 * notification-listener access, POST_NOTIFICATIONS, unrestricted battery (reusing
 * E20-04's [BatteryOnboardingViewModel] rather than duplicating its logic), then Scan Mac QR.
 *
 * Framework-free: calls [permissionRequester] instead of `Settings`/`ActivityResultContracts`
 * directly, so it stays plain `unit:` tested against fakes (CLAUDE.md's Robolectric rule).
 */
class OnboardingViewModel(
    private val batteryOnboardingViewModel: BatteryOnboardingViewModel,
    private val permissionRequester: PermissionRequester,
) {
    /**
     * The fixed onboarding order, minus BATTERY once [BatteryOnboardingViewModel.shouldShowScreen]
     * is already false (e.g. the exemption is already granted).
     */
    fun steps(): List<OnboardingStep> {
        val steps =
            mutableListOf(
                OnboardingStep.IDENTITY,
                OnboardingStep.NOTIFICATION_LISTENER,
                OnboardingStep.POST_NOTIFICATIONS,
            )
        if (batteryOnboardingViewModel.shouldShowScreen()) {
            steps += OnboardingStep.BATTERY
        }
        steps += OnboardingStep.SCAN_QR
        return steps
    }

    /** This device's manufacturer, passed through to the reused [BatteryOnboardingScreen]. */
    fun batteryManufacturer(): String = batteryOnboardingViewModel.manufacturer()

    /** The OEM guidance entry, passed through to the reused [BatteryOnboardingScreen]. */
    fun batteryOemGuidance(): OemGuidanceEntry = batteryOnboardingViewModel.oemGuidance()

    /**
     * Called when the user taps "Allow" on [step]'s screen; requests the matching permission
     * through [permissionRequester]. A no-op for steps with no permission request of their own
     * (identity, battery, scan) -- battery and camera each keep their own existing request path.
     */
    fun allow(step: OnboardingStep) {
        val permission =
            when (step) {
                OnboardingStep.NOTIFICATION_LISTENER -> OnboardingPermission.NOTIFICATION_LISTENER
                OnboardingStep.POST_NOTIFICATIONS -> OnboardingPermission.POST_NOTIFICATIONS
                OnboardingStep.IDENTITY, OnboardingStep.BATTERY, OnboardingStep.SCAN_QR -> return
            }
        permissionRequester.request(permission)
    }
}
