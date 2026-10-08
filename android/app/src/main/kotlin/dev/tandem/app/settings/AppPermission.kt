package dev.tandem.app.settings

import android.Manifest

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
    val label: String,
    val reason: String,
    val access: PermissionAccess,
) {
    NOTIFICATIONS(
        label = "Notifications",
        reason = "Show Tandem's own alerts.",
        access = PermissionAccess.Runtime(listOf(Manifest.permission.POST_NOTIFICATIONS)),
    ),
    NOTIFICATION_ACCESS(
        label = "Notification access",
        reason = "Show your phone's notifications on your Mac.",
        access = PermissionAccess.NotificationListener,
    ),
    SMS(
        label = "SMS",
        reason = "Read and send texts from your Mac.",
        access = PermissionAccess.Runtime(listOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS)),
    ),
    CONTACTS(
        label = "Contacts",
        reason = "Show names for texts and calls.",
        access = PermissionAccess.Runtime(listOf(Manifest.permission.READ_CONTACTS)),
    ),
    PHONE(
        label = "Phone",
        reason = "Show calls on your Mac, and answer or place them from there.",
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
        label = "Caller ID",
        reason = "Show who is calling on your Mac. Tandem never blocks or changes calls.",
        access = PermissionAccess.CallScreeningRole,
    ),
    CAMERA(
        label = "Camera",
        reason = "Scan the code on your Mac. Decoded on this phone.",
        access = PermissionAccess.Runtime(listOf(Manifest.permission.CAMERA)),
    ),
    LOCAL_NETWORK(
        label = "Local network",
        reason = "Find your Mac on this network.",
        access = PermissionAccess.Runtime(listOf(Manifest.permission.ACCESS_LOCAL_NETWORK)),
    ),
    BATTERY(
        label = "Battery",
        reason = "Stay connected while the app is in the background.",
        access = PermissionAccess.BatteryExemption,
    ),
    ACCESSIBILITY(
        label = "Accessibility",
        reason = "Let your Mac tap and type while you mirror.",
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
