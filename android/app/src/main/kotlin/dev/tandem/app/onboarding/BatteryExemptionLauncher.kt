package dev.tandem.app.onboarding

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

internal fun batteryExemptionIntent(packageName: String): Intent =
    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))

/**
 * Opens the system's direct "Let app always run in background?" dialog (F-4.1); only when no
 * activity handles it does it fall back to the all-apps battery-optimization list.
 */
@Suppress("ImplicitInternalIntent") // the Settings actions are genuinely external.
fun launchBatteryExemption(context: Context) {
    try {
        context.startActivity(batteryExemptionIntent(context.packageName))
    } catch (_: ActivityNotFoundException) {
        context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }
}
