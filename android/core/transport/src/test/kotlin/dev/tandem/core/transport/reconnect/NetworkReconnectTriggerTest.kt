package dev.tandem.core.transport.reconnect

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * NetworkReconnectTrigger tests (E20-07; `docs/planning/backlog/phase-2.yaml` E20-07's `tdd:`
 * list). [FakeNetworkMonitor] lets a test emit availability events on demand;
 * [dev.tandem.core.testing.TestClock] ties the trigger's debounce window to the same
 * `testScheduler` the `ReconnectStrategy`'s `StandardTestDispatcher` uses, so both advance
 * together (E00-18).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NetworkReconnectTriggerTest {
    @Test
    fun networkReconnectTrigger_networkAvailable_connectsImmediatelyAndResetsBackoff() =
        runTest {
            val callTimes = mutableListOf<Long>()
            val connector =
                FakeConnector { _ ->
                    callTimes += testScheduler.currentTime
                    ConnectResult.Unreachable
                }
            val strategy = newStrategy(connector)
            val monitor = FakeNetworkMonitor()
            val trigger = newTrigger(monitor, strategy)

            strategy.start()
            trigger.start()
            runCurrent() // first cycle's only candidate fails; strategy now waiting out its 1s backoff

            // Still well inside the pending 1s wait -- a real reconnect wait would not fire again
            // until t=1000ms.
            advanceTimeBy(200.milliseconds)
            monitor.emit()
            runCurrent()

            // The kicked attempt happened at ~200ms, not at the full 1000ms backoff.
            assertEquals(listOf(0L, 200L), callTimes)

            // Backoff was reset to 1s by the kick: the next failure (from this kicked attempt)
            // waits 1s again, not 2s.
            advanceTimeBy(1.seconds)
            runCurrent()
            assertEquals(listOf(0L, 200L, 1200L), callTimes)

            strategy.close()
            trigger.close()
        }

    @Test
    fun networkReconnectTrigger_fiveEventsWithin500ms_oneImmediateAttempt() =
        runTest {
            val callTimes = mutableListOf<Long>()
            val connector =
                FakeConnector { _ ->
                    callTimes += testScheduler.currentTime
                    ConnectResult.Unreachable
                }
            val strategy = newStrategy(connector)
            val monitor = FakeNetworkMonitor()
            val trigger = newTrigger(monitor, strategy)

            strategy.start()
            trigger.start()
            runCurrent() // first cycle fails; strategy waiting out its 1s backoff

            repeat(FIVE) {
                monitor.emit()
                runCurrent()
                advanceTimeBy(50.milliseconds)
            }

            // Exactly one extra attempt from the burst, not five.
            assertEquals(2, callTimes.size)

            strategy.close()
            trigger.close()
        }

    private fun TestScope.newStrategy(connector: Connector): ReconnectStrategy =
        ReconnectStrategy(
            connector = connector,
            bonjourSource = BonjourCandidateSource { emptyList() },
            pairingAddressSource = PairingAddressSource { listOf(CandidateAddress("10.0.0.9", 7443)) },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

    private fun TestScope.newTrigger(
        monitor: FakeNetworkMonitor,
        strategy: ReconnectStrategy,
    ): NetworkReconnectTrigger =
        NetworkReconnectTrigger(
            networkMonitor = monitor,
            reconnectStrategy = strategy,
            clock = TestClock(testScheduler),
            dispatcher = StandardTestDispatcher(testScheduler),
        )

    private class FakeConnector(
        val result: (CandidateAddress) -> ConnectResult,
    ) : Connector {
        override suspend fun connect(candidate: CandidateAddress): ConnectResult = result(candidate)
    }

    private class FakeNetworkMonitor : NetworkMonitor {
        private val events = MutableSharedFlow<Unit>(extraBufferCapacity = Int.MAX_VALUE)
        override val available: Flow<Unit> = events

        suspend fun emit() {
            events.emit(Unit)
        }
    }

    private companion object {
        const val FIVE = 5
    }
}
