package dev.tandem.feature.mirror

import android.view.Surface
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.asCoroutineDispatcher
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** E61-11 unit tests (`docs/planning/backlog/phase-6.yaml` E61-11's `tdd:` list). Plain JUnit5. */
class MirrorSessionLifecycleTest {
    private class BlockingEncoder : VideoEncoder {
        val closes = AtomicInteger()
        val pumping = CountDownLatch(1)
        private val closed = CountDownLatch(1)

        override fun requestSyncFrame() = Unit

        override fun setBitrate(bitsPerSecond: Int) = Unit

        override fun nextOutput(): EncodedBuffer? {
            pumping.countDown()
            closed.await()
            return null
        }

        override fun close() {
            closes.incrementAndGet()
            closed.countDown()
        }
    }

    private class RecordingCapture : CaptureSource {
        val stops = AtomicInteger()
        private var listener: () -> Unit = {}

        override fun start(surface: Surface) = Unit

        override fun stop() {
            stops.incrementAndGet()
        }

        override fun setStopListener(listener: () -> Unit) {
            this.listener = listener
        }

        fun revokeProjection() = listener()
    }

    private class RecordingStream(
        private val failWrites: Boolean = false,
    ) : ByteStream {
        val closes = AtomicInteger()
        override val input: InputStream = ByteArrayInputStream(ByteArray(0))
        override val output: OutputStream =
            object : OutputStream() {
                override fun write(b: Int) {
                    if (failWrites) throw IOException("connection dropped")
                }
            }

        override fun closeGracefully() {
            closes.incrementAndGet()
        }

        override fun closeAbruptly() = Unit
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val encoder = BlockingEncoder()
    private val capture = RecordingCapture()
    private val session = FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }
    private val indicatorStops = AtomicInteger()
    private val indicatorNotified = CountDownLatch(1)

    @AfterEach
    fun tearDown() {
        executor.shutdownNow()
    }

    private fun lifecycle(stream: RecordingStream): MirrorSessionLifecycle {
        val pipeline =
            EncodePipeline(
                encoderFactory =
                    EncoderFactory { _, _ ->
                        encoder
                    },
                capture = capture,
                config = EncoderConfigBuilder.build(sdkInt = 30),
                stream = stream,
                ioDispatcher = executor.asCoroutineDispatcher(),
            )
        return MirrorSessionLifecycle(
            pipeline = pipeline,
            session = session,
            indicator =
                MirrorIndicator {
                    indicatorStops.incrementAndGet()
                    indicatorNotified.countDown()
                },
            scope = CoroutineScope(Dispatchers.Unconfined + Job()),
        ).also { it.start() }
    }

    private fun awaitStopped() {
        assertTrue(indicatorNotified.await(AWAIT_SECONDS, TimeUnit.SECONDS))
    }

    private fun assertEachReleasedOnce(stream: RecordingStream) {
        assertEquals(1, encoder.closes.get())
        assertEquals(1, capture.stops.get())
        assertEquals(1, stream.closes.get())
        assertEquals(1, indicatorStops.get())
    }

    @Test
    fun mirrorSession_projectionOnStopCallback_releasesDisplayCodecAndProjection() {
        val stream = RecordingStream()
        lifecycle(stream)
        assertTrue(encoder.pumping.await(AWAIT_SECONDS, TimeUnit.SECONDS))

        capture.revokeProjection()
        awaitStopped()

        assertEachReleasedOnce(stream)
    }

    @Test
    fun mirrorSession_controlSessionEnded_releasesAllMirrorResources() {
        val stream = RecordingStream()
        lifecycle(stream)
        assertTrue(encoder.pumping.await(AWAIT_SECONDS, TimeUnit.SECONDS))

        session.emitState(ConnectionState.Disconnected())
        awaitStopped()

        assertEachReleasedOnce(stream)
    }

    @Test
    fun mirrorSession_stopCalledTwice_releasesEachResourceOnce() {
        val stream = RecordingStream()
        val lifecycle = lifecycle(stream)
        assertTrue(encoder.pumping.await(AWAIT_SECONDS, TimeUnit.SECONDS))

        lifecycle.stop()
        lifecycle.stop()
        awaitStopped()

        assertEachReleasedOnce(stream)
    }

    @Test
    fun mirrorSession_mediaConnectionDrops_releasesAllMirrorResources() {
        val stream = RecordingStream(failWrites = true)
        lifecycle(stream)

        awaitStopped()

        assertEachReleasedOnce(stream)
    }

    private companion object {
        const val AWAIT_SECONDS = 5L
    }
}
