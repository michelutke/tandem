package dev.tandem.app.onboarding

import androidx.annotation.StringRes
import dev.tandem.app.R

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
    LOCAL_NETWORK,
}

/** One numbered row of the permissions screen (ui-spec §7.2 Onboarding · Permissions). */
enum class PermissionRow(
    @StringRes val labelRes: Int,
    @StringRes val reasonRes: Int,
    val permissions: List<OnboardingPermission>,
) {
    NOTIFICATIONS(
        labelRes = R.string.permission_notifications_label,
        reasonRes = R.string.permission_notifications_reason,
        permissions = listOf(OnboardingPermission.POST_NOTIFICATIONS, OnboardingPermission.NOTIFICATION_LISTENER),
    ),
    BATTERY(
        labelRes = R.string.permission_battery_label,
        reasonRes = R.string.permission_battery_reason,
        permissions = listOf(OnboardingPermission.BATTERY),
    ),
    CAMERA(
        labelRes = R.string.permission_camera_label,
        reasonRes = R.string.permission_camera_reason,
        permissions = listOf(OnboardingPermission.CAMERA),
    ),
    SMS_AND_CALLS(
        labelRes = R.string.permission_sms_label,
        reasonRes = R.string.permission_sms_reason,
        permissions = listOf(OnboardingPermission.SMS_AND_CALLS),
    ),
    LOCAL_NETWORK(
        labelRes = R.string.permission_local_network_label,
        reasonRes = R.string.permission_local_network_reason,
        permissions = listOf(OnboardingPermission.LOCAL_NETWORK),
    ),
}
