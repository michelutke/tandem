package dev.tandem.app.onboarding

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat

/**
 * Seam over the permission-requesting actions onboarding performs: runtime permission dialogs and
 * the system Settings screens for special accesses (notification listener, battery). Lets
 * [OnboardingViewModel.allow] stay plain unit-tested against a recording fake.
 * [SystemPermissionRequester] is the only production implementation.
 */
fun interface PermissionRequester {
    fun request(permission: OnboardingPermission)
}

/** Seam over the current grant state of each [OnboardingPermission]. */
fun interface PermissionChecker {
    fun isGranted(permission: OnboardingPermission): Boolean
}

private val SMS_AND_CALLS_PERMISSIONS =
    arrayOf(
        Manifest.permission.READ_SMS,
        Manifest.permission.SEND_SMS,
        Manifest.permission.READ_PHONE_STATE,
        Manifest.permission.READ_CONTACTS,
    )

/**
 * Production implementation. Runtime permissions need an Activity Result launcher, which only the
 * hosting activity can register; [requestRuntimePermissions] is that launcher's `launch` call.
 * A denied permission leaves its feature off; it can be granted later from system Settings.
 */
class SystemPermissionRequester(
    private val context: Context,
    private val requestRuntimePermissions: (Array<String>) -> Unit,
) : PermissionRequester {
    @Suppress("ImplicitInternalIntent") // the Settings actions below are genuinely external.
    override fun request(permission: OnboardingPermission) {
        when (permission) {
            OnboardingPermission.POST_NOTIFICATIONS -> {
                requestRuntimePermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
            }

            OnboardingPermission.CAMERA -> {
                requestRuntimePermissions(arrayOf(Manifest.permission.CAMERA))
            }

            OnboardingPermission.SMS_AND_CALLS -> {
                requestRuntimePermissions(SMS_AND_CALLS_PERMISSIONS)
            }

            OnboardingPermission.NOTIFICATION_LISTENER -> {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }

            OnboardingPermission.BATTERY -> {
                launchBatteryExemption(context)
            }
        }
    }
}

class SystemPermissionChecker(
    private val context: Context,
) : PermissionChecker {
    override fun isGranted(permission: OnboardingPermission): Boolean =
        when (permission) {
            OnboardingPermission.POST_NOTIFICATIONS -> {
                hasRuntime(Manifest.permission.POST_NOTIFICATIONS)
            }

            OnboardingPermission.CAMERA -> {
                hasRuntime(Manifest.permission.CAMERA)
            }

            OnboardingPermission.SMS_AND_CALLS -> {
                SMS_AND_CALLS_PERMISSIONS.all(::hasRuntime)
            }

            OnboardingPermission.NOTIFICATION_LISTENER -> {
                context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)
            }

            OnboardingPermission.BATTERY -> {
                context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
            }
        }

    private fun hasRuntime(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}
