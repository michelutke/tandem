package dev.tandem.core.designsystem

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.WindowInsetsController
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView

/**
 * Light status and navigation bar icons while a dark surface (scanner, ringing, mirror; ui-spec §3.1)
 * is on screen, so they stay visible on it; the previous appearance returns when it leaves.
 */
@Composable
fun DarkSystemBars() {
    val view = LocalView.current
    if (view.isInEditMode) return
    DisposableEffect(view) {
        val controller =
            view.context
                .findActivity()
                ?.window
                ?.insetsController
        val previous = controller?.systemBarsAppearance
        controller?.setSystemBarsAppearance(0, LIGHT_BARS)
        onDispose {
            if (previous != null) controller.setSystemBarsAppearance(previous, LIGHT_BARS)
        }
    }
}

private const val LIGHT_BARS =
    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
