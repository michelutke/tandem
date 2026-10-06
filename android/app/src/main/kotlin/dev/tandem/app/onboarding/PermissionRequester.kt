package dev.tandem.app.onboarding

import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * Seam over the two permission-requesting actions this onboarding sequence performs (E20-14):
 * notification-listener access (no runtime dialog exists for this special access -- only the
 * system's dedicated Settings screen) and the POST_NOTIFICATIONS runtime permission.
 * [OnboardingViewModel.allow] calls this instead of touching `Settings`/
 * `ActivityResultContracts` directly, so it stays plain unit-tested against a recording fake
 * (CLAUDE.md's Robolectric rule). Battery-optimization and CAMERA each already have their own
 * request path ([BatteryOnboardingScreen], [dev.tandem.feature.pairing.scan.ScannerScreen]) and
 * are deliberately not routed through this seam. [SystemPermissionRequester] is the only
 * production implementation.
 */
fun interface PermissionRequester {
    fun request(permission: OnboardingPermission)
}

/**
 * Production implementation. POST_NOTIFICATIONS needs a real runtime-permission launcher, which
 * only a Composable can create (`rememberLauncherForActivityResult`); [requestPostNotifications]
 * is that launcher's `launch` call, wired in by whichever composition root constructs this class.
 */
class SystemPermissionRequester(
    private val context: Context,
    private val requestPostNotifications: () -> Unit,
) : PermissionRequester {
    @Suppress("ImplicitInternalIntent") // Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS is genuinely external.
    override fun request(permission: OnboardingPermission) {
        when (permission) {
            OnboardingPermission.NOTIFICATION_LISTENER -> {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }

            OnboardingPermission.POST_NOTIFICATIONS -> {
                requestPostNotifications()
            }
        }
    }
}
