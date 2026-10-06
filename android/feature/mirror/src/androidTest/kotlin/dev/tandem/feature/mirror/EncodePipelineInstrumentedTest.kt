package dev.tandem.feature.mirror

import android.graphics.Bitmap
import android.graphics.Color
import android.view.Surface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.RequiresDevice
import dev.tandem.core.transport.ByteStream
import dev.tandem.protocol.v1.MediaMessage
import dev.tandem.protocol.v1.Orientation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.random.Random

/**
 * E61-03 instrumented tdd on the emulator's software AVC encoder (E00-21):
 * `encodePipeline_emulatorSoftwareAvcEncoder_firstIdrWithin1s`,
 * `encodePipeline_keyframeRequestOnSoftwareCodec_idrWithinNext2Frames` and
 * `encodePipeline_cbr4MbpsOnSoftwareCodec_bitrateWithin20Percent`. A canvas-drawing capture stands
 * in for MediaProjection, which needs the system consent dialog (E61-02).
 */
@RunWith(AndroidJUnit4::class)
class EncodePipelineInstrumentedTest {
    private class CanvasCapture(
        private val noiseFrames: List<Bitmap>,
    ) : CaptureSource {
        @Volatile
        private var running = false
        private var drawer: Thread? = null

        override fun start(surface: Surface) {
            stop()
            running = true
            drawer =
                thread {
                    var tick = 0
                    try {
                        while (running) {
                            val canvas = surface.lockCanvas(null)
                            canvas.drawBitmap(noiseFrames[tick % NOISE_FRAME_COUNT], 0f, 0f, null)
                            surface.unlockCanvasAndPost(canvas)
                            tick++
                            Thread.sleep(FRAME_INTERVAL_MILLIS)
                        }
                    } catch (_: IllegalArgumentException) {
                        running = false
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

    private val noiseFrames = List(NOISE_FRAME_COUNT) { noiseBitmap(Random(it)) }

    private fun noiseBitmap(random: Random): Bitmap {
        val blocksPerRow = FRAME_WIDTH / NOISE_BLOCK_PX
        val blockColors =
            IntArray(blocksPerRow * (FRAME_HEIGHT / NOISE_BLOCK_PX)) {
                Color.rgb(random.nextInt(COLOR_MAX), random.nextInt(COLOR_MAX), random.nextInt(COLOR_MAX))
            }
        val pixels =
            IntArray(FRAME_WIDTH * FRAME_HEIGHT) {
                val blockRow = it / FRAME_WIDTH / NOISE_BLOCK_PX
                blockColors[blockRow * blocksPerRow + it % FRAME_WIDTH / NOISE_BLOCK_PX]
            }
        return Bitmap.createBitmap(pixels, FRAME_WIDTH, FRAME_HEIGHT, Bitmap.Config.ARGB_8888)
    }

    private fun encode(
        config: EncoderConfig,
        durationMillis: Long,
        onFrame: (VideoEncoder, EncodedBuffer) -> Unit = { _, _ -> },
    ): List<Output> {
        val outputs = mutableListOf<Output>()
        val capture = CanvasCapture(noiseFrames)
        val encoder = MediaCodecEncoderFactory().create(config, capture)
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(durationMillis)
        try {
            while (System.nanoTime() < deadline) {
                val buffer = encoder.nextOutput()
                if (buffer == null) {
                    Thread.sleep(POLL_MILLIS)
                    continue
                }
                outputs += Output(buffer, System.nanoTime())
                onFrame(encoder, buffer)
            }
        } finally {
            capture.stop()
            encoder.close()
        }
        return outputs
    }

    private val config =
        EncoderConfigBuilder
            .build()
            .copy(width = FRAME_WIDTH, height = FRAME_HEIGHT)

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
    @RequiresDevice
    fun encodePipeline_cbr4MbpsOnSoftwareCodec_bitrateWithin20Percent() {
        val target = 4_000_000
        val outputs = encode(config.copy(bitrateBitsPerSecond = target), durationMillis = 10_000)

        val seconds = (outputs.last().atNanos - outputs.first().atNanos) / NANOS_PER_SECOND
        val measured = outputs.sumOf { it.buffer.data.size } * BITS_PER_BYTE / seconds
        assertEquals(target.toDouble(), measured, target * 0.2)
    }

    private class TimedStream : ByteStream {
        val messages = CopyOnWriteArrayList<Pair<Long, MediaMessage>>()
        override val input: InputStream = ByteArrayInputStream(ByteArray(0))
        override val output: OutputStream =
            object : OutputStream() {
                override fun write(b: Int) = Unit

                override fun write(
                    b: ByteArray,
                    off: Int,
                    len: Int,
                ) {
                    messages +=
                        System.nanoTime() to MediaMessage.parseFrom(b.copyOfRange(off + LENGTH_PREFIX_BYTES, off + len))
                }
            }

        override fun closeGracefully() = Unit

        override fun closeAbruptly() = Unit
    }

    private class ManualDisplayChanges : DisplayChangeSource {
        lateinit var listener: (DisplayGeometry) -> Unit

        override fun start(listener: (DisplayGeometry) -> Unit) {
            this.listener = listener
        }

        override fun stop() = Unit
    }

    /** E61-05 `encodePipeline_emulatorRotation_newDimensionsWithin500ms`; the display event stands in for `adb emu rotate`. */
    @Test
    @RequiresDevice
    fun encodePipeline_emulatorRotation_newDimensionsWithin500ms() {
        val stream = TimedStream()
        val displayChanges = ManualDisplayChanges()
        val pipeline =
            EncodePipeline(
                MediaCodecEncoderFactory(),
                CanvasCapture(noiseFrames),
                config,
                stream,
                Dispatchers.IO,
                displayChanges,
            )
        val runner = thread { runBlocking { pipeline.run() } }
        Thread.sleep(SETTLE_MILLIS)
        val lastBefore = stream.messages.last { it.second.hasMediaFrame() }.first

        displayChanges.listener(DisplayGeometry(config.height, config.width, Orientation.ORIENTATION_PORTRAIT))
        Thread.sleep(SETTLE_MILLIS)
        pipeline.stop()
        runner.join()

        val rotation = stream.messages.indexOfFirst { it.second.hasRotationChanged() }
        assertTrue(rotation >= 0)
        assertEquals(
            config.height,
            stream.messages[rotation + 1]
                .second.mediaFormat.width,
        )
        val firstAfter =
            stream.messages
                .drop(rotation + 2)
                .first { it.second.hasMediaFrame() }
                .first
        assertTrue(firstAfter - lastBefore <= TimeUnit.MILLISECONDS.toNanos(ROTATION_BUDGET_MILLIS))
    }

    private companion object {
        const val SETTLE_MILLIS = 2_000L
        const val POLL_MILLIS = 10L
        const val ROTATION_BUDGET_MILLIS = 500L
        const val LENGTH_PREFIX_BYTES = 4
        const val COLOR_MAX = 256
        const val FRAME_WIDTH = 1280
        const val FRAME_HEIGHT = 720
        const val NOISE_FRAME_COUNT = 4
        const val NOISE_BLOCK_PX = 8
        const val FRAME_INTERVAL_MILLIS = 33L
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val BITS_PER_BYTE = 8
    }
}
