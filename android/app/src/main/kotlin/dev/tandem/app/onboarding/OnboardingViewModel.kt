package dev.tandem.app.onboarding

/**
 * View model for the onboarding sequence (F-4.1, F-1.1, UC-02): identity bootstrap, welcome,
 * permissions, then Scan Mac QR.
 *
 * Framework-free: calls [permissionRequester] and reads [permissionChecker] instead of
 * `Settings`/`ActivityResultContracts`/`checkSelfPermission` directly, so it stays plain `unit:`
 * tested against fakes (CLAUDE.md's Robolectric rule).
 */
class OnboardingViewModel(
    private val permissionRequester: PermissionRequester,
    private val permissionChecker: PermissionChecker,
) {
    fun steps(): List<OnboardingStep> =
        listOf(
            OnboardingStep.IDENTITY,
            OnboardingStep.WELCOME,
            OnboardingStep.PERMISSIONS,
            OnboardingStep.SCAN_QR,
        )

    fun rows(): List<PermissionRow> = PermissionRow.entries

    fun isGranted(row: PermissionRow): Boolean = row.permissions.all(permissionChecker::isGranted)

    /**
     * Called when the user taps [row]: requests its first missing permission. A row with two
     * permissions (notifications) therefore takes one tap each, since the runtime dialog and the
     * system Settings screen cannot be shown at once.
     */
    fun allow(row: PermissionRow) {
        row.permissions.firstOrNull { !permissionChecker.isGranted(it) }?.let(permissionRequester::request)
    }
}
