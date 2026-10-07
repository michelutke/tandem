package dev.tandem.app.onboarding

/**
 * The individual permissions and special accesses onboarding can request through
 * [PermissionRequester] and read through [PermissionChecker]. A closed set by design: later
 * features (media, accessibility, notification policy) are never requested during onboarding.
 */
enum class OnboardingPermission {
    POST_NOTIFICATIONS,
    NOTIFICATION_LISTENER,
    BATTERY,
    CAMERA,
    SMS_AND_CALLS,
}

/** One numbered row of the permissions screen (ui-spec §7.2 Onboarding · Permissions). */
enum class PermissionRow(
    val label: String,
    val reason: String,
    val permissions: List<OnboardingPermission>,
) {
    NOTIFICATIONS(
        label = "Notifications",
        reason = "Show your phone's notifications on your Mac.",
        permissions = listOf(OnboardingPermission.POST_NOTIFICATIONS, OnboardingPermission.NOTIFICATION_LISTENER),
    ),
    BATTERY(
        label = "Battery",
        reason = "Stay connected while the app is in the background.",
        permissions = listOf(OnboardingPermission.BATTERY),
    ),
    CAMERA(
        label = "Camera",
        reason = "Scan the code on your Mac. Decoded on this phone.",
        permissions = listOf(OnboardingPermission.CAMERA),
    ),
    SMS_AND_CALLS(
        label = "SMS & calls",
        reason = "Read and send texts, and show who is calling.",
        permissions = listOf(OnboardingPermission.SMS_AND_CALLS),
    ),
}
