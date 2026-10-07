package dev.tandem.app.onboarding

/** Test fake standing in for [PermissionChecker]; [granted] is mutable so tests can simulate a grant. */
class FakePermissionChecker(
    val granted: MutableSet<OnboardingPermission> = mutableSetOf(),
) : PermissionChecker {
    override fun isGranted(permission: OnboardingPermission): Boolean = permission in granted
}
