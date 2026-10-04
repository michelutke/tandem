package dev.tandem.feature.mirror

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.view.Surface

/** Real [CaptureSource]: mirrors the display of an already-consented [projection] into the encoder surface. */
class MediaProjectionCaptureSource(
    private val projection: MediaProjection,
    private val width: Int,
    private val height: Int,
    private val densityDpi: Int,
) : CaptureSource {
    private var virtualDisplay: VirtualDisplay? = null

    private val callback =
        object : MediaProjection.Callback() {
            override fun onStop() {
                virtualDisplay?.release()
                virtualDisplay = null
            }
        }

    override fun start(surface: Surface) {
        projection.registerCallback(callback, null)
        virtualDisplay =
            projection.createVirtualDisplay(
                DISPLAY_NAME,
                width,
                height,
                densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface,
                null,
                null,
            )
    }

    override fun stop() {
        virtualDisplay?.release()
        virtualDisplay = null
        projection.unregisterCallback(callback)
        projection.stop()
    }

    private companion object {
        const val DISPLAY_NAME = "tandem-mirror"
    }
}
