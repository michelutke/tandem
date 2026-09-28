package dev.tandem.app.onboarding

/** Test fake (E20-14 tdd) standing in for [PermissionRequester]; records every call in order. */
class RecordingPermissionRequester : PermissionRequester {
    private val _requested = mutableListOf<OnboardingPermission>()
    val requested: List<OnboardingPermission> get() = _requested

    override fun request(permission: OnboardingPermission) {
        _requested += permission
    }
}
