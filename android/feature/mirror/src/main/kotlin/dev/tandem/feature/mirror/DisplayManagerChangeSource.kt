package dev.tandem.feature.mirror

import android.hardware.display.DisplayManager
import android.os.Handler
import android.util.DisplayMetrics
import android.view.Display
import android.view.Surface
import dev.tandem.protocol.v1.Orientation

/** Real [DisplayChangeSource]: reports rotation and resolution changes of the default display. */
class DisplayManagerChangeSource(
    private val displayManager: DisplayManager,
    private val handler: Handler,
) : DisplayChangeSource {
    private var displayListener: DisplayManager.DisplayListener? = null

    override fun start(listener: (DisplayGeometry) -> Unit) {
        val registered =
            object : DisplayManager.DisplayListener {
                override fun onDisplayAdded(displayId: Int) = Unit

                override fun onDisplayRemoved(displayId: Int) = Unit

                override fun onDisplayChanged(displayId: Int) {
                    if (displayId == Display.DEFAULT_DISPLAY) listener(currentGeometry())
                }
            }
        displayListener = registered
        displayManager.registerDisplayListener(registered, handler)
    }

    override fun stop() {
        displayListener?.let(displayManager::unregisterDisplayListener)
        displayListener = null
    }

    @Suppress("DEPRECATION")
    private fun currentGeometry(): DisplayGeometry {
        val display = displayManager.getDisplay(Display.DEFAULT_DISPLAY)
        val metrics = DisplayMetrics()
        display.getRealMetrics(metrics)
        return DisplayGeometry(metrics.widthPixels, metrics.heightPixels, display.rotation.toOrientation())
    }

    private fun Int.toOrientation(): Orientation =
        when (this) {
            Surface.ROTATION_90 -> Orientation.ORIENTATION_LANDSCAPE
            Surface.ROTATION_180 -> Orientation.ORIENTATION_REVERSE_PORTRAIT
            Surface.ROTATION_270 -> Orientation.ORIENTATION_REVERSE_LANDSCAPE
            else -> Orientation.ORIENTATION_PORTRAIT
        }
}
