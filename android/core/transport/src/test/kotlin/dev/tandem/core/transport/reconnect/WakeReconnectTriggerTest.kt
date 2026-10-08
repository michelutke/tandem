package dev.tandem.core.transport.reconnect

import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.milliseconds

/** WakeReconnectTrigger tests: screen-on, Doze exit and foreground kick the strategy out of backoff. */
@OptIn(ExperimentalCoroutinesApi::class)
class WakeReconnectTriggerTest {
    private class FakeIdleSource(
        initialIdle: Boolean = false,
    ) : DeviceIdleSource {
        val idle = MutableStateFlow(initialIdle)
        val screen = MutableSharedFlow<Unit>(extraBufferCapacity = 8)
        override val isIdle: StateFlow<Boolean> = idle
        override val screenOn: Flow<Unit> = screen
    }

    private class Harness(
        scope: TestScope,
        val idleSource: FakeIdleSource,
    ) {
        val callTimes = mutableListOf<Long>()
        val foreground = MutableSharedFlow<Unit>(extraBufferCapacity = 8)
        val strategy =
            ReconnectStrategy(
                connector =
                    Connector {
                        callTimes += scope.testScheduler.currentTime
                        ConnectResult.Unreachable
                    },
                bonjourSource = BonjourCandidateSource { emptyList() },
                pairingAddressSource = PairingAddressSource { listOf(CandidateAddress("10.0.0.9", 7443)) },
                dispatcher = StandardTestDispatcher(scope.testScheduler),
            )
        val trigger =
            WakeReconnectTrigger(
                deviceIdleSource = idleSource,
                reconnectStrategy = strategy,
                clock = TestClock(scope.testScheduler),
                dispatcher = StandardTestDispatcher(scope.testScheduler),
                foreground = foreground,
            )

        fun close() {
            strategy.close()
            trigger.close()
        }
    }

    private suspend fun TestScope.inBackoff(
        idleSource: FakeIdleSource = FakeIdleSource(),
        block: suspend Harness.() -> Unit,
    ) {
        val harness = Harness(this, idleSource)
        harness.strategy.start()
        harness.trigger.start()
        runCurrent() // first cycle fails; strategy waiting out its 1s backoff
        advanceTimeBy(200.milliseconds)
        harness.block()
        harness.close()
    }

    @Test
    fun wakeReconnectTrigger_screenOnDuringBackoff_kicksImmediately() =
        runTest {
            inBackoff {
                idleSource.screen.emit(Unit)
                runCurrent()

                assertEquals(listOf(0L, 200L), callTimes)
            }
        }

    @Test
    fun wakeReconnectTrigger_dozeExit_kicks() =
        runTest {
            inBackoff(FakeIdleSource(initialIdle = true)) {
                idleSource.idle.value = false
                runCurrent()

                assertEquals(listOf(0L, 200L), callTimes)
            }
        }

    @Test
    fun wakeReconnectTrigger_initialNotIdle_noKick() =
        runTest {
            inBackoff {
                runCurrent()

                assertEquals(listOf(0L), callTimes)
            }
        }

    @Test
    fun wakeReconnectTrigger_enteringDoze_noKick() =
        runTest {
            inBackoff {
                idleSource.idle.value = true
                runCurrent()

                assertEquals(listOf(0L), callTimes)
            }
        }

    @Test
    fun wakeReconnectTrigger_appForegrounded_kicks() =
        runTest {
            inBackoff {
                foreground.emit(Unit)
                runCurrent()

                assertEquals(listOf(0L, 200L), callTimes)
            }
        }

    @Test
    fun wakeReconnectTrigger_screenOnAndForegroundWithin500ms_oneAttempt() =
        runTest {
            inBackoff {
                idleSource.screen.emit(Unit)
                runCurrent()
                advanceTimeBy(50.milliseconds)
                foreground.emit(Unit)
                runCurrent()

                assertEquals(2, callTimes.size)
            }
        }
}
