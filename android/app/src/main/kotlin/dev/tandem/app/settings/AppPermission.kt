package dev.tandem.app.settings

import android.Manifest
import androidx.annotation.StringRes
import dev.tandem.app.R

/** How an [AppPermission] is granted: a runtime dialog or one of the special-access Settings pages. */
sealed interface PermissionAccess {
    data class Runtime(
        val manifestPermissions: List<String>,
    ) : PermissionAccess

    data object NotificationListener : PermissionAccess

    data object BatteryExemption : PermissionAccess

    data object Accessibility : PermissionAccess

    data object CallScreeningRole : PermissionAccess
}

/** Every permission and special access the app uses, in the order Settings lists them. */
enum class AppPermission(
    @StringRes val label: Int,
    @StringRes val reason: Int,
    val access: PermissionAccess,
) {
    NOTIFICATIONS(
        label = R.string.app_permission_notifications_label,
        reason = R.string.app_permission_notifications_reason,
        access = PermissionAccess.Runtime(listOf(Manifest.permission.POST_NOTIFICATIONS)),
    ),
    NOTIFICATION_ACCESS(
        label = R.string.app_permission_notification_access_label,
        reason = R.string.app_permission_notification_access_reason,
        access = PermissionAccess.NotificationListener,
    ),
    SMS(
        label = R.string.app_permission_sms_label,
        reason = R.string.app_permission_sms_reason,
        access = PermissionAccess.Runtime(listOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS)),
    ),
    CONTACTS(
        label = R.string.app_permission_contacts_label,
        reason = R.string.app_permission_contacts_reason,
        access = PermissionAccess.Runtime(listOf(Manifest.permission.READ_CONTACTS)),
    ),
    PHONE(
        label = R.string.app_permission_phone_label,
        reason = R.string.app_permission_phone_reason,
        access =
            PermissionAccess.Runtime(
                listOf(
                    Manifest.permission.READ_PHONE_STATE,
                    Manifest.permission.ANSWER_PHONE_CALLS,
                    Manifest.permission.CALL_PHONE,
                ),
            ),
    ),
    CALLER_ID(
        label = R.string.app_permission_caller_id_label,
        reason = R.string.app_permission_caller_id_reason,
        access = PermissionAccess.CallScreeningRole,
    ),
    CAMERA(
        label = R.string.app_permission_camera_label,
        reason = R.string.app_permission_camera_reason,
        access = PermissionAccess.Runtime(listOf(Manifest.permission.CAMERA)),
    ),
    LOCAL_NETWORK(
        label = R.string.app_permission_local_network_label,
        reason = R.string.app_permission_local_network_reason,
        access = PermissionAccess.Runtime(listOf(Manifest.permission.ACCESS_LOCAL_NETWORK)),
    ),
    BATTERY(
        label = R.string.app_permission_battery_label,
        reason = R.string.app_permission_battery_reason,
        access = PermissionAccess.BatteryExemption,
    ),
    ACCESSIBILITY(
        label = R.string.app_permission_accessibility_label,
        reason = R.string.app_permission_accessibility_reason,
        access = PermissionAccess.Accessibility,
    ),
}

data class PermissionStatus(
    val permission: AppPermission,
    val granted: Boolean,
)

/** Seam over the grant state and request actions of [AppPermission]s, so screens stay unit-testable. */
interface AppPermissionGateway {
    fun isGranted(permission: AppPermission): Boolean

    /** Requests [permission], or opens the Settings page that manages it when a dialog cannot help. */
    fun request(permission: AppPermission)
}

object NoAppPermissions : AppPermissionGateway {
    override fun isGranted(permission: AppPermission): Boolean = false

    override fun request(permission: AppPermission) = Unit
}

fun AppPermissionGateway.statuses(): List<PermissionStatus> =
    AppPermission.entries.map { PermissionStatus(it, isGranted(it)) }
