package dev.tandem.app.settings

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import dev.tandem.app.onboarding.hasLocalNetworkAccess
import dev.tandem.app.onboarding.launchBatteryExemption
import dev.tandem.feature.input.AccessibilitySettingsLauncher
import dev.tandem.feature.input.AccessibilityStateSource
import dev.tandem.feature.input.SettingsSecureAccessibilityStateSource

/**
 * Production [AppPermissionGateway]. A runtime permission is requested through
 * [requestRuntimePermissions] (the hosting activity's result launcher) once per process; after
 * that, or once granted, a tap opens the app's system permission page, because Android stops
 * showing a dialog after repeated denials. Special accesses open their own Settings page.
 */
class SystemAppPermissionGateway(
    private val context: Context,
    private val requestRuntimePermissions: (Array<String>) -> Unit,
    private val accessibilityState: AccessibilityStateSource = SettingsSecureAccessibilityStateSource(context),
) : AppPermissionGateway {
    private val alreadyRequested = mutableSetOf<AppPermission>()

    override fun isGranted(permission: AppPermission): Boolean =
        when (val access = permission.access) {
            is PermissionAccess.Runtime -> {
                if (permission == AppPermission.LOCAL_NETWORK) {
                    hasLocalNetworkAccess(context)
                } else {
                    access.manifestPermissions.all(::hasRuntime)
                }
            }

            PermissionAccess.NotificationListener -> {
                context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)
            }

            PermissionAccess.BatteryExemption -> {
                context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
            }

            PermissionAccess.Accessibility -> {
                accessibilityState.isServiceEnabled()
            }
        }

    @Suppress("ImplicitInternalIntent") // the Settings actions below are genuinely external.
    override fun request(permission: AppPermission) {
        when (val access = permission.access) {
            is PermissionAccess.Runtime -> {
                if (isGranted(permission) || !alreadyRequested.add(permission)) {
                    openAppDetails()
                } else {
                    requestRuntimePermissions(access.manifestPermissions.toTypedArray())
                }
            }

            PermissionAccess.NotificationListener -> {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }

            PermissionAccess.BatteryExemption -> {
                if (isGranted(permission)) {
                    context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                } else {
                    launchBatteryExemption(context)
                }
            }

            PermissionAccess.Accessibility -> {
                AccessibilitySettingsLauncher(context).open()
            }
        }
    }

    private fun hasRuntime(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun openAppDetails() {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
        )
    }
}
