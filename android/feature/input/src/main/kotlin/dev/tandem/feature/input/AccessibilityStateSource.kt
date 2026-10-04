package dev.tandem.feature.input

import android.content.Context
import android.content.Intent
import android.provider.Settings

interface AccessibilityStateSource {
    fun isServiceEnabled(): Boolean
}

class SettingsSecureAccessibilityStateSource(
    private val context: Context,
) : AccessibilityStateSource {
    override fun isServiceEnabled(): Boolean {
        val enabledServices =
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        val serviceClassName = TandemAccessibilityService::class.java.name
        return enabledServices.split(':').any { it.substringAfter('/') == serviceClassName }
    }
}

class AccessibilitySettingsLauncher(
    private val context: Context,
) {
    @Suppress("ImplicitInternalIntent") // Settings.ACTION_ACCESSIBILITY_SETTINGS is genuinely external.
    fun open() {
        context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
