package dev.tandem.feature.clipboard

import android.content.Context
import android.provider.Settings

/** Whether the user has switched [ClipboardCaptureService] on in the system Accessibility settings. */
class ClipboardCaptureServiceState(
    private val context: Context,
) {
    fun isServiceEnabled(): Boolean {
        val enabledServices =
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        val serviceClassName = ClipboardCaptureService::class.java.name
        return enabledServices.split(':').any { it.substringAfter('/') == serviceClassName }
    }
}
