package dev.tandem.feature.mirror

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.view.Surface

/** Real [CaptureSource]: mirrors the display of an already-consented [projection] into the encoder surface. */
class MediaProjectionCaptureSource(
    private val projection: MediaProjection,
    private var width: Int,
    private var height: Int,
    private val densityDpi: Int,
) : CaptureSource {
    private var virtualDisplay: VirtualDisplay? = null
    private var callbackRegistered = false
    private var stopListener: () -> Unit = {}

    private val callback =
        object : MediaProjection.Callback() {
            override fun onStop() {
                virtualDisplay?.release()
                virtualDisplay = null
                stopListener()
            }
        }

    override fun setStopListener(listener: () -> Unit) {
        stopListener = listener
    }

    override fun resize(
        width: Int,
        height: Int,
    ) {
        this.width = width
        this.height = height
    }

    override fun start(surface: Surface) {
        virtualDisplay?.release()
        if (!callbackRegistered) projection.registerCallback(callback, null)
        callbackRegistered = true
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
