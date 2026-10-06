package dev.tandem.feature.mirror

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.view.Surface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.io.OutputStream
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * E61-11 instrumented tdd on the emulator (E00-21):
 * `mirrorSession_tenStartStopCycles_codecAndDisplayCountsUnchanged`. A private VirtualDisplay
 * stands in for MediaProjection, which needs the system consent dialog (E61-02).
 */
@RunWith(AndroidJUnit4::class)
class MirrorSessionTeardownInstrumentedTest {
    private class DisplayCapture(
        private val displayManager: DisplayManager,
    ) : CaptureSource {
        private var display: VirtualDisplay? = null

        override fun start(surface: Surface) {
            display = displayManager.createVirtualDisplay("tandem-teardown-test", WIDTH, HEIGHT, DPI, surface, 0)
        }

        override fun stop() {
            display?.release()
            display = null
        }
    }

    private class CountingEncoderFactory : EncoderFactory {
        val liveCodecs = AtomicInteger()
        private val delegate = MediaCodecEncoderFactory()

        override fun create(
            config: EncoderConfig,
            capture: CaptureSource,
        ): VideoEncoder {
            val encoder = delegate.create(config, capture)
            liveCodecs.incrementAndGet()
            return object : VideoEncoder by encoder {
                override fun close() {
                    encoder.close()
                    liveCodecs.decrementAndGet()
                }
            }
        }
    }

    private class DiscardingStream : ByteStream {
        override val input: InputStream = ByteArrayInputStream(ByteArray(0))
        override val output: OutputStream =
            object : OutputStream() {
                override fun write(b: Int) = Unit
            }

        override fun closeGracefully() = Unit

        override fun closeAbruptly() = Unit
    }

    @Test
    fun mirrorSession_tenStartStopCycles_codecAndDisplayCountsUnchanged() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val factory = CountingEncoderFactory()
        val displaysBefore = displayManager.displays.size
        val config =
            EncoderConfigBuilder
                .build()
                .copy(width = WIDTH, height = HEIGHT)

        repeat(CYCLES) {
            val session = FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }
            val scope = CoroutineScope(Dispatchers.Default + Job())
            val stopped = CountDownLatch(1)
            val lifecycle =
                MirrorSessionLifecycle(
                    pipeline =
                        EncodePipeline(
                            encoderFactory = factory,
                            capture = DisplayCapture(displayManager),
                            config = config,
                            stream = DiscardingStream(),
                            ioDispatcher = Dispatchers.IO,
                        ),
                    session = session,
                    indicator = { stopped.countDown() },
                    scope = scope,
                )
            lifecycle.start()
            Thread.sleep(RUN_MILLIS)
            lifecycle.stop()
            assertTrue(stopped.await(AWAIT_SECONDS, TimeUnit.SECONDS))
            runBlocking {
                scope.coroutineContext.job.children
                    .forEach { it.join() }
            }
            scope.cancel()
        }

        assertEquals(0, factory.liveCodecs.get())
        assertEquals(displaysBefore, displayManager.displays.size)
    }

    private companion object {
        const val CYCLES = 10
        const val WIDTH = 1280
        const val HEIGHT = 720
        const val DPI = 320
        const val RUN_MILLIS = 300L
        const val AWAIT_SECONDS = 5L
    }
}
