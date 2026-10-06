package dev.tandem.feature.mirror

import android.view.Surface
import dev.tandem.core.transport.ByteStream
import dev.tandem.protocol.v1.MediaFrame
import dev.tandem.protocol.v1.MediaMessage
import dev.tandem.protocol.v1.Orientation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer

/** EncodePipeline E61-03 unit tests (`docs/planning/backlog/phase-6.yaml` E61-03's `tdd:` list). Plain JUnit5. */
class EncodePipelineTest {
    private class FakeEncoder(
        private val outputs: ArrayDeque<EncodedBuffer>,
    ) : VideoEncoder {
        var syncRequests = 0
        val bitrates = mutableListOf<Int>()

        override fun requestSyncFrame() {
            syncRequests++
        }

        override fun setBitrate(bitsPerSecond: Int) {
            bitrates += bitsPerSecond
        }

        var onFirstOutput: () -> Unit = {}

        override fun nextOutput(): EncodedBuffer? {
            onFirstOutput()
            onFirstOutput = {}
            return outputs.removeFirstOrNull()
        }

        override fun close() = Unit
    }

    private class FakeCapture : CaptureSource {
        val events = mutableListOf<String>()

        override fun resize(
            width: Int,
            height: Int,
        ) {
            events += "resize ${width}x$height"
        }

        override fun start(surface: Surface) = recordStart()

        fun recordStart() {
            events += "start"
        }

        override fun stop() = Unit
    }

    private class CapturingStream : ByteStream {
        val bytes = ByteArrayOutputStream()
        override val input: InputStream = ByteArrayInputStream(ByteArray(0))
        override val output: OutputStream = bytes

        override fun closeGracefully() = Unit

        override fun closeAbruptly() = Unit
    }

    private fun buffer(
        size: Int,
        pts: Long,
        key: Boolean = false,
        config: Boolean = false,
    ) = EncodedBuffer(ByteArray(size), pts, key, config)

    private fun run(
        vararg outputs: EncodedBuffer,
        encoderHook: (FakeEncoder, EncodePipeline) -> Unit = { _, _ -> },
    ): Pair<FakeEncoder, List<MediaMessage>> {
        val encoder = FakeEncoder(ArrayDeque(outputs.toList()))
        val stream = CapturingStream()
        val pipeline =
            EncodePipeline(
                encoderFactory = { _, _ -> encoder },
                capture = FakeCapture(),
                config = EncoderConfigBuilder.build(),
                stream = stream,
                ioDispatcher = Dispatchers.Unconfined,
            )
        encoderHook(encoder, pipeline)
        runBlocking { pipeline.run() }
        return encoder to parse(stream.bytes.toByteArray())
    }

    private fun parse(bytes: ByteArray): List<MediaMessage> {
        val buffer = ByteBuffer.wrap(bytes)
        val messages = mutableListOf<MediaMessage>()
        while (buffer.hasRemaining()) {
            val body = ByteArray(buffer.int)
            buffer.get(body)
            messages += MediaMessage.parseFrom(body)
        }
        return messages
    }

    private fun List<MediaMessage>.frames(): List<MediaFrame> = filter { it.hasMediaFrame() }.map { it.mediaFrame }

    @Test
    fun encodePipeline_keyframeRequestReceived_requestsSyncFrameOnce() {
        val (encoder, _) =
            run(buffer(10, pts = 1, key = true)) { encoder, pipeline ->
                encoder.onFirstOutput =
                    pipeline::onKeyframeRequest
            }

        assertEquals(1, encoder.syncRequests)
    }

    @Test
    fun encodePipeline_encoderOutputBuffer_emitsMediaFrameWithPtsAndKeyFlag() {
        val (_, messages) = run(buffer(10, pts = 33_000, key = true), buffer(5, pts = 66_000))

        val frames = messages.frames()
        assertEquals(listOf(33_000L, 66_000L), frames.map { it.pts })
        assertEquals(listOf(MediaFrameFragmenter.FLAG_KEYFRAME, 0), frames.map { it.flags })
        assertEquals(10, frames[0].data.size())
    }

    @Test
    fun encodePipeline_codecConfigBuffer_sentFirstAsConfigFlaggedFrame() {
        val (_, messages) = run(buffer(8, pts = 0, config = true), buffer(10, pts = 1, key = true))

        assertTrue(messages.first().hasMediaFormat())
        val frames = messages.frames()
        assertEquals(MediaFrameFragmenter.FLAG_CODEC_CONFIG, frames.first().flags)
        assertEquals(MediaFrameFragmenter.FLAG_KEYFRAME, frames[1].flags)
    }

    @Test
    fun encodePipeline_accessUnit2500KiB_sentAsThreeFragmentsSamePts() {
        val (_, messages) = run(buffer(2500 * 1024, pts = 777, key = true))

        val frames = messages.frames()
        assertEquals(3, frames.size)
        assertEquals(listOf(0, 1, 2), frames.map { it.fragmentIndex })
        assertEquals(listOf(3, 3, 3), frames.map { it.fragmentCount })
        assertEquals(listOf(777L, 777L, 777L), frames.map { it.pts })
        assertTrue(frames.all { it.data.size() <= MediaFrameFragmenter.MAX_FRAGMENT_BYTES })
        assertEquals(2500 * 1024, frames.sumOf { it.data.size() })
    }

    @Test
    fun encodePipeline_accessUnitNeedingNineFragments_notSentBitrateLoweredIdrRequested() {
        val (encoder, messages) = run(buffer(8 * 960 * 1024 + 1, pts = 5, key = true))

        assertTrue(messages.frames().isEmpty())
        assertEquals(listOf(EncoderConfigBuilder.build(30).bitrateBitsPerSecond / 2), encoder.bitrates)
        assertEquals(1, encoder.syncRequests)
    }

    private class FakeDisplayChanges : DisplayChangeSource {
        var listener: (DisplayGeometry) -> Unit = {}

        override fun start(listener: (DisplayGeometry) -> Unit) {
            this.listener = listener
        }

        override fun stop() = Unit
    }

    private class RotationRun(
        val created: MutableList<EncoderConfig>,
        val capture: FakeCapture,
        val messages: List<MediaMessage>,
    )

    private fun runWithRotation(geometry: DisplayGeometry): RotationRun {
        val stream = CapturingStream()
        val capture = FakeCapture()
        val created = mutableListOf<EncoderConfig>()
        val displayChanges = FakeDisplayChanges()
        val oldEncoder = FakeEncoder(ArrayDeque(listOf(buffer(10, pts = 1, key = true))))
        val newEncoder = FakeEncoder(ArrayDeque(listOf(buffer(10, pts = 2, key = true))))
        oldEncoder.onFirstOutput = { displayChanges.listener(geometry) }
        val encoders = ArrayDeque(listOf(oldEncoder, newEncoder))
        val pipeline =
            EncodePipeline(
                encoderFactory = { config, _ ->
                    created += config
                    capture.recordStart()
                    encoders.removeFirst()
                },
                capture = capture,
                config = EncoderConfigBuilder.build(),
                stream = stream,
                ioDispatcher = Dispatchers.Unconfined,
                displayChanges = displayChanges,
            )
        runBlocking { pipeline.run() }
        return RotationRun(created, capture, parse(stream.bytes.toByteArray()))
    }

    private val landscape = DisplayGeometry(2208, 1840, Orientation.ORIENTATION_LANDSCAPE)

    @Test
    fun rotationPlanner_portraitToLandscape_swapsWidthAndHeight() {
        assertEquals(EncoderSize(1920, 1080), RotationPlanner.rotate(1080, 1920))
    }

    @Test
    fun rotationPlanner_foldable2208x1840_scaledTo1920x1600() {
        assertEquals(EncoderSize(1920, 1600), RotationPlanner.plan(2208, 1840))
    }

    @Test
    fun encodePipeline_rotationEvent_emitsRotationChangedBeforeNextFrame() {
        val messages = runWithRotation(landscape).messages

        val rotationIndex = messages.indexOfFirst { it.hasRotationChanged() }
        assertEquals(Orientation.ORIENTATION_LANDSCAPE, messages[rotationIndex].rotationChanged.orientation)
        assertTrue(messages[rotationIndex + 1].hasMediaFormat())
        assertEquals(1600, messages[rotationIndex + 1].mediaFormat.height)
        assertEquals(0, messages.take(rotationIndex).count { it.hasMediaFrame() })
        assertEquals(
            2L,
            messages
                .drop(rotationIndex + 2)
                .first { it.hasMediaFrame() }
                .mediaFrame.pts,
        )
    }

    @Test
    fun encodePipeline_rotationEvent_recreatesEncoderAndDisplayAtPlannedSize() {
        val run = runWithRotation(landscape)

        assertEquals(listOf(1920 to 1080, 1920 to 1600), run.created.map { it.width to it.height })
        assertEquals(listOf("start", "resize 1920x1600", "start"), run.capture.events)
    }
}
