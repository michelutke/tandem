package dev.tandem.core.transport.heartbeat

import dev.tandem.core.protocol.multiplex.FrameArrival
import dev.tandem.core.testing.ManualElapsedRealtime
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * [ControlFrameRateCap] tests (E20-15; SPEC.md D-61/D-66, phone side): more than 60 non-Heartbeat
 * `CONTROL` frames inside a sliding 1 s window exceed the cap; Heartbeats and feature-channel frames
 * never count.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ControlFrameRateCapTest {
    private val received = MutableSharedFlow<FrameArrival>(extraBufferCapacity = 256)
    private val elapsed = ManualElapsedRealtime()
    private var exceededCount = 0

    private fun kotlinx.coroutines.test.TestScope.startCap() {
        ControlFrameRateCap(
            received = received,
            elapsedRealtimeSource = elapsed,
            onExceeded = { exceededCount++ },
            dispatcher = StandardTestDispatcher(testScheduler),
        ).start()
        runCurrent()
    }

    private suspend fun emitControl(
        count: Int,
        isHeartbeat: Boolean = false,
    ) {
        repeat(count) { received.emit(FrameArrival(Channel.CHANNEL_CONTROL, isHeartbeat)) }
    }

    @Test
    fun controlFrameRateCap_sixtyControlFramesInOneSecond_notExceeded() =
        runTest {
            startCap()

            emitControl(60)
            runCurrent()

            assertEquals(0, exceededCount)
        }

    @Test
    fun controlFrameRateCap_sixtyOneControlFramesInOneSecond_exceeded() =
        runTest {
            startCap()

            emitControl(61)
            runCurrent()

            assertEquals(1, exceededCount)
        }

    @Test
    fun controlFrameRateCap_heartbeatsAndFeatureFrames_notCounted() =
        runTest {
            startCap()

            emitControl(200, isHeartbeat = true)
            repeat(200) { received.emit(FrameArrival(Channel.CHANNEL_NOTIFY, isHeartbeat = false)) }
            runCurrent()

            assertEquals(0, exceededCount)
        }

    @Test
    fun controlFrameRateCap_framesSpreadOverSlidingWindow_notExceeded() =
        runTest {
            startCap()

            emitControl(40)
            runCurrent()
            elapsed.advanceBy(1_001)
            emitControl(40)
            runCurrent()

            assertEquals(0, exceededCount)
        }

    @Test
    fun controlFrameRateCap_burstStraddlingWindowBoundary_exceeded() =
        runTest {
            startCap()

            emitControl(40)
            runCurrent()
            elapsed.advanceBy(500)
            emitControl(21)
            runCurrent()

            assertEquals(1, exceededCount)
        }
}
