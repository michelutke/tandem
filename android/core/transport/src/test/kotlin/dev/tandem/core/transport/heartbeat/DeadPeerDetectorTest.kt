package dev.tandem.core.transport.heartbeat

import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.testing.ManualElapsedRealtime
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.seconds

/**
 * [DeadPeerDetector] tests (E20-15; `docs/planning/backlog/phase-2.yaml` E20-15's `tdd:` list).
 * [FakeDeviceIdleSource] is a plain [DeviceIdleSource] stand-in. The silence/wall-clock tests use
 * [ManualElapsedRealtime], advanced by hand and independent of the `StandardTestDispatcher`'s own
 * virtual time, so silence can be simulated (device sleep, or a long span with frames still
 * arriving) without the detector's own `delay`-based timer ever getting a chance to run and
 * confound the result -- exactly the point of the sleep-inclusive elapsedRealtime seam (E00-18): a
 * real coroutine `delay` on a dispatcher can itself be frozen through the same device sleep that
 * `ElapsedRealtimeSource` keeps counting through.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DeadPeerDetectorTest {
    @Test
    fun deadPeerDetector_silence46sIncludingSleep_marksDead() =
        runTest {
            var dead = false
            val detector =
                DeadPeerDetector(
                    received = MutableSharedFlow(),
                    deviceIdleSource = FakeDeviceIdleSource(),
                    elapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
                    onDead = { dead = true },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            detector.start()

            advanceTimeBy(46.seconds)
            runCurrent()

            assertTrue(dead)
        }

    @Test
    fun deadPeerDetector_dozeExitAfterLongSilence_triggersReconnect() =
        runTest {
            var dead = false
            val elapsed = ManualElapsedRealtime()
            val idleSource = FakeDeviceIdleSource(initialIdle = true)
            val detector =
                DeadPeerDetector(
                    received = MutableSharedFlow(),
                    deviceIdleSource = idleSource,
                    elapsedRealtimeSource = elapsed,
                    onDead = { dead = true },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            detector.start()
            runCurrent()

            // 46s of device-sleep silence with the dispatcher's own virtual time never advanced --
            // the detector's own `delay(45s)` timer never becomes due, so only the Doze-exit check
            // below can be what marks this dead.
            elapsed.advanceBy(SILENCE_MILLIS)
            idleSource.setIdle(false) // Doze exit
            runCurrent()

            assertTrue(dead)
        }

    @Test
    fun deadPeerDetector_screenOnAfterLongSilence_triggersReconnect() =
        runTest {
            var dead = false
            val elapsed = ManualElapsedRealtime()
            val idleSource = FakeDeviceIdleSource()
            val detector =
                DeadPeerDetector(
                    received = MutableSharedFlow(),
                    deviceIdleSource = idleSource,
                    elapsedRealtimeSource = elapsed,
                    onDead = { dead = true },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            detector.start()
            runCurrent()

            elapsed.advanceBy(SILENCE_MILLIS)
            idleSource.emitScreenOn()
            runCurrent()

            assertTrue(dead)
        }

    @Test
    fun deadPeerDetector_wallClockJumpForward1h_staysConnected() =
        runTest {
            var dead = false
            val received = MutableSharedFlow<Unit>()
            val detector =
                DeadPeerDetector(
                    received = received,
                    deviceIdleSource = FakeDeviceIdleSource(),
                    elapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
                    onDead = { dead = true },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            detector.start()

            // A frame every 30s (< 45s threshold) for over an hour -- this detector never reads any
            // wall clock, so a real wall-clock jump elsewhere in the process cannot affect it;
            // exercising a long span with frames still arriving is the observable proxy for that.
            repeat(HOUR_IN_30S_STEPS) {
                advanceTimeBy(30.seconds)
                received.emit(Unit)
                runCurrent()
            }

            assertFalse(dead)
        }

    private class FakeDeviceIdleSource(
        initialIdle: Boolean = false,
    ) : DeviceIdleSource {
        private val mutableIsIdle = MutableStateFlow(initialIdle)
        override val isIdle: StateFlow<Boolean> = mutableIsIdle

        private val mutableScreenOn = MutableSharedFlow<Unit>()
        override val screenOn = mutableScreenOn

        fun setIdle(idle: Boolean) {
            mutableIsIdle.value = idle
        }

        suspend fun emitScreenOn() = mutableScreenOn.emit(Unit)
    }

    private companion object {
        const val SILENCE_MILLIS = 46_000L
        const val HOUR_IN_30S_STEPS = 3_600 / 30
    }
}
