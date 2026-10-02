package dev.tandem.feature.clipboard

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService

/**
 * E31-12: Quick Settings "Send clip" tile. A tile click cannot read the clipboard itself
 * (background reads are blocked on Android 10+), so it collapses the shade and starts the
 * transparent [ClipboardCaptureActivity], which reads on window focus and sends.
 */
class ClipboardTileService : TileService() {
    internal var activityLauncher: (Intent) -> Unit = ::startActivityAndCollapseCompat

    override fun onClick() {
        activityLauncher(Intent(this, ClipboardCaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun startActivityAndCollapseCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent =
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, ClipboardCaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_IMMUTABLE,
                )
            startActivityAndCollapse(pendingIntent)
        } else {
            @SuppressLint("StartActivityAndCollapseDeprecated")
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
