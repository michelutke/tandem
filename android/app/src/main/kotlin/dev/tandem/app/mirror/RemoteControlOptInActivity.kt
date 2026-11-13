package dev.tandem.app.mirror

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemTheme
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.input.AccessibilitySettingsLauncher
import dev.tandem.feature.input.RemoteInputSettingsScreen
import dev.tandem.feature.input.SettingsSecureAccessibilityStateSource

/**
 * Hosts the remote control opt-in (ui-spec §7.2), opened from the "View only." notification the
 * mirror shows when Accessibility is off. Not exported. Open Accessibility settings hands over to
 * system Settings; View only just closes the screen and mirroring carries on without input.
 */
class RemoteControlOptInActivity : TandemActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val accessibilityState = SettingsSecureAccessibilityStateSource(this)
        setContent {
            TandemTheme {
                RemoteInputSettingsScreen(
                    accessibilityState = accessibilityState,
                    onOpenAccessibilitySettings = {
                        AccessibilitySettingsLauncher(this).open()
                        finish()
                    },
                    onViewOnly = ::finish,
                    modifier = Modifier.fillMaxSize().safeDrawingPadding(),
                )
            }
        }
    }

    companion object {
        fun pendingIntent(context: Context): PendingIntent =
            PendingIntent.getActivity(
                context,
                0,
                Intent(context, RemoteControlOptInActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
    }
}
