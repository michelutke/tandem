package dev.tandem.app.settings

/** Test fake for [AppPermissionGateway]; [granted] is mutable so tests can simulate a grant. */
class RecordingPermissionGateway(
    val granted: MutableSet<AppPermission> = mutableSetOf(),
) : AppPermissionGateway {
    val requested = mutableListOf<AppPermission>()

    override fun isGranted(permission: AppPermission): Boolean = permission in granted

    override fun request(permission: AppPermission) {
        requested += permission
    }
}
