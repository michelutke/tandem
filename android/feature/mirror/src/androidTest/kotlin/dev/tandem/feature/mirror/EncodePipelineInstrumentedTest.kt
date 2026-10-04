package dev.tandem.feature.mirror

import android.graphics.Color
import android.view.Surface
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * E61-03 instrumented tdd on the emulator's software AVC encoder (E00-21):
 * `encodePipeline_emulatorSoftwareAvcEncoder_firstIdrWithin1s`,
 * `encodePipeline_keyframeRequestOnSoftwareCodec_idrWithinNext2Frames` and
 * `encodePipeline_cbr4MbpsOnSoftwareCodec_bitrateWithin20Percent`. A canvas-drawing capture stands
 * in for MediaProjection, which needs the system consent dialog (E61-02).
 */
@RunWith(AndroidJUnit4::class)
class EncodePipelineInstrumentedTest {
    private class CanvasCapture : CaptureSource {
        @Volatile
        private var running = false
        private var drawer: Thread? = null

        override fun start(surface: Surface) {
            running = true
            drawer =
                thread {
                    var tick = 0
                    while (running) {
                        val canvas = surface.lockCanvas(null)
                        canvas.drawColor(Color.rgb(tick % COLOR_MAX, (tick * 3) % COLOR_MAX, (tick * 7) % COLOR_MAX))
                        surface.unlockCanvasAndPost(canvas)
                        tick++
                        Thread.sleep(FRAME_INTERVAL_MILLIS)
                    }
                }
        }

        override fun stop() {
            running = false
            drawer?.join()
        }
    }

    private class Output(
        val buffer: EncodedBuffer,
        val atNanos: Long,
    )

    private fun encode(
        config: EncoderConfig,
        durationMillis: Long,
        onFrame: (VideoEncoder, EncodedBuffer) -> Unit = { _, _ -> },
    ): List<Output> {
        val outputs = mutableListOf<Output>()
        val capture = CanvasCapture()
        val encoder = MediaCodecEncoderFactory().create(config, capture)
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(durationMillis)
        try {
            while (System.nanoTime() < deadline) {
                val buffer = encoder.nextOutput() ?: break
                outputs += Output(buffer, System.nanoTime())
                onFrame(encoder, buffer)
            }
        } finally {
            encoder.close()
            capture.stop()
        }
        return outputs
    }

    private val config =
        EncoderConfigBuilder
            .build(sdkInt = android.os.Build.VERSION.SDK_INT)
            .copy(width = 1280, height = 720)

    @Test
    fun encodePipeline_emulatorSoftwareAvcEncoder_firstIdrWithin1s() {
        val start = System.nanoTime()
        val outputs = encode(config, durationMillis = 1_000)

        val firstIdr = outputs.first { it.buffer.isKeyFrame }
        assertTrue(firstIdr.atNanos - start <= TimeUnit.SECONDS.toNanos(1))
        assertTrue(outputs.first().buffer.isCodecConfig)
    }

    @Test
    fun encodePipeline_keyframeRequestOnSoftwareCodec_idrWithinNext2Frames() {
        var requested = false
        var framesSinceRequest = 0
        var idrFrameDistance = -1
        encode(config, durationMillis = 4_000) { encoder, buffer ->
            if (buffer.isCodecConfig) return@encode
            if (requested && idrFrameDistance < 0) {
                framesSinceRequest++
                if (buffer.isKeyFrame) idrFrameDistance = framesSinceRequest
            } else if (!requested && !buffer.isKeyFrame) {
                requested = true
                encoder.requestSyncFrame()
            }
        }

        assertTrue("IDR distance $idrFrameDistance", idrFrameDistance in 1..2)
    }

    @Test
    fun encodePipeline_cbr4MbpsOnSoftwareCodec_bitrateWithin20Percent() {
        val target = 4_000_000
        val outputs = encode(config.copy(bitrateBitsPerSecond = target), durationMillis = 10_000)

        val seconds = (outputs.last().atNanos - outputs.first().atNanos) / NANOS_PER_SECOND
        val measured = outputs.sumOf { it.buffer.data.size } * BITS_PER_BYTE / seconds
        assertEquals(target.toDouble(), measured, target * 0.2)
    }

    private companion object {
        const val COLOR_MAX = 256
        const val FRAME_INTERVAL_MILLIS = 33L
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val BITS_PER_BYTE = 8
    }
}
