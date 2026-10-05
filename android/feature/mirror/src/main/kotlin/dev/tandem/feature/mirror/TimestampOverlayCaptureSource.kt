package dev.tandem.feature.mirror

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.media.ImageReader
import android.os.Handler
import android.view.Surface

/**
 * Harness-only [CaptureSource] decorator (E61-08): routes the display into an intermediate [ImageReader],
 * burns a [TimestampOverlayEncoder] cell row into each frame and draws it onto the encoder surface. Never
 * constructed on a non-debuggable build. Frame pixels are never logged (invariant 7).
 */
class TimestampOverlayCaptureSource(
    private val delegate: CaptureSource,
    private val wallClockMs: () -> Long,
    private var width: Int,
    private var height: Int,
    private val handler: Handler,
) : CaptureSource {
    private var reader: ImageReader? = null
    private var output: Surface? = null
    private var frameIndex = 0L
    private val paint = Paint()

    override fun start(surface: Surface) {
        reader?.close()
        output = surface
        val created = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, READER_IMAGES)
        created.setOnImageAvailableListener(::onImageAvailable, handler)
        reader = created
        delegate.start(created.surface)
    }

    override fun resize(
        width: Int,
        height: Int,
    ) {
        this.width = width
        this.height = height
        delegate.resize(width, height)
    }

    override fun stop() {
        try {
            delegate.stop()
        } finally {
            reader?.close()
            reader = null
        }
    }

    override fun setStopListener(listener: () -> Unit) = delegate.setStopListener(listener)

    private fun onImageAvailable(source: ImageReader) {
        val image = source.acquireLatestImage() ?: return
        image.use {
            val plane = it.planes[0]
            val stridePixels = plane.rowStride / plane.pixelStride
            val bitmap = Bitmap.createBitmap(stridePixels, it.height, Bitmap.Config.ARGB_8888)
            bitmap.copyPixelsFromBuffer(plane.buffer)
            val target = output ?: return
            val canvas = target.lockCanvas(null)
            try {
                val frame = Rect(0, 0, it.width, it.height)
                canvas.drawBitmap(bitmap, frame, frame, null)
                drawOverlay(canvas)
            } finally {
                target.unlockCanvasAndPost(canvas)
                bitmap.recycle()
            }
        }
    }

    private fun drawOverlay(canvas: Canvas) {
        val clock = wallClockMs()
        val cell = TimestampOverlayEncoder.CELL_SIZE
        for (bit in 0 until TimestampOverlayEncoder.TOTAL_BITS) {
            paint.color = if (TimestampOverlayEncoder.bitAt(bit, frameIndex, clock)) Color.WHITE else Color.BLACK
            canvas.drawRect((bit * cell).toFloat(), 0f, ((bit + 1) * cell).toFloat(), cell.toFloat(), paint)
        }
        frameIndex++
    }

    private companion object {
        const val READER_IMAGES = 3
    }
}
