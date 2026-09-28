package dev.tandem.core.transport.reconnect

import app.cash.turbine.test
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.seconds

/**
 * ReconnectStrategy tests (E20-06; `docs/planning/backlog/phase-2.yaml` E20-06's `tdd:` list).
 * Every strategy here shares its `runTest` scope's `StandardTestDispatcher`, so backoff `delay`s
 * advance in virtual time (E00-18). [FakeConnector] scripts a [ConnectResult] per call and
 * records the dial order and, where a test measures backoff, `testScheduler.currentTime`. Because
 * a [FakeConnector] that never returns [ConnectResult.Connected] drives an infinite retry loop,
 * every test drives time with bounded `runCurrent`/`advanceTimeBy` calls rather than
 * `advanceUntilIdle`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ReconnectStrategyTest {
    @Test
    fun reconnectStrategy_allCandidateKinds_triesLastWorkingThenBonjourThenPairing() =
        runTest {
            val lastWorking = CandidateAddress("10.0.0.1", 7443)
            val bonjour1 = CandidateAddress("10.0.0.2", 7443)
            val bonjour2 = CandidateAddress("10.0.0.3", 7443)
            val pairing1 = CandidateAddress("10.0.0.4", 7443)
            // Also listed as a pairing-time address, and equal to bonjour1: must be tried once.
            val duplicateOfBonjour1 = bonjour1

            val connector = FakeConnector { ConnectResult.Unreachable }
            val strategy =
                newStrategy(
                    connector = connector,
                    bonjour = { listOf(bonjour1, bonjour2) },
                    pairing = { listOf(duplicateOfBonjour1, pairing1) },
                    initialLastWorking = lastWorking,
                )

            strategy.start()
            runCurrent() // runs exactly one full cycle; the backoff delay() suspends it after

            assertEquals(listOf(lastWorking, bonjour1, bonjour2, pairing1), connector.calls)
            // Still retrying (every candidate failed): close it so runTest's teardown doesn't
            // drain this never-ending loop.
            strategy.close()
        }

    @Test
    fun reconnectBackoff_consecutiveFailedCycles_waits1s2s4s8s16s30s30s() =
        runTest {
            val onlyCandidate = CandidateAddress("10.0.0.9", 7443)
            val callTimes = mutableListOf<Long>()
            val connector =
                FakeConnector { _ ->
                    callTimes += testScheduler.currentTime
                    ConnectResult.Unreachable
                }
            val strategy =
                newStrategy(connector = connector, bonjour = { emptyList() }, pairing = { listOf(onlyCandidate) })

            strategy.start()
            // 1 + 2 + 4 + 8 + 16 + 30 + 30 = 91s covers 7 waits (8 attempts); 100s leaves margin.
            advanceTimeBy(100.seconds)
            runCurrent()

            val waits = callTimes.zipWithNext { a, b -> (b - a) / MILLIS_PER_SECOND }
            assertEquals(listOf(1L, 2L, 4L, 8L, 16L, 30L, 30L), waits.take(SEQUENCE_LENGTH))
            strategy.close()
        }

    @Test
    fun reconnectStrategy_success_resetsBackoffTo1sAndRecordsAddress() =
        runTest {
            val working = CandidateAddress("10.0.0.6", 7443)
            val callTimes = mutableListOf<Long>()
            var cycleCount = 0
            val connector =
                FakeConnector { _ ->
                    cycleCount++
                    callTimes += testScheduler.currentTime
                    if (cycleCount == SUCCESS_ON_CYCLE) ConnectResult.Connected else ConnectResult.Unreachable
                }
            val strategy = newStrategy(connector = connector, bonjour = { emptyList() }, pairing = { listOf(working) })

            strategy.lastWorking.test {
                assertNull(awaitItem())
                strategy.start()
                // Two failed cycles (waits 1s, 2s) precede the 3rd cycle's success.
                advanceTimeBy(4.seconds)
                runCurrent()
                assertEquals(working, awaitItem())
            }
            val waitsBeforeSuccess = callTimes.zipWithNext { a, b -> (b - a) / MILLIS_PER_SECOND }
            assertEquals(listOf(1L, 2L), waitsBeforeSuccess)

            // Restarting after success (e.g. a later disconnect, E12-08) must wait 1s before its
            // next retry, not continue from the 2 failed cycles already spent before the success.
            strategy.start()
            advanceTimeBy(5.seconds)
            runCurrent()

            val waitAfterRestart = (callTimes[4] - callTimes[3]) / MILLIS_PER_SECOND
            assertEquals(1L, waitAfterRestart)
            strategy.close()
        }

    @Test
    fun reconnectStrategy_lastWorkingAddressPinMismatch_triesNextCandidate() =
        runTest {
            val impostor = CandidateAddress("10.0.0.7", 7443)
            val genuine = CandidateAddress("10.0.0.8", 7443)
            val connector =
                FakeConnector { address ->
                    when (address) {
                        impostor -> ConnectResult.PinMismatch
                        genuine -> ConnectResult.Connected
                        else -> ConnectResult.Unreachable
                    }
                }
            val strategy =
                newStrategy(
                    connector = connector,
                    bonjour = { listOf(genuine) },
                    pairing = { emptyList() },
                    initialLastWorking = impostor,
                )

            strategy.start()
            runCurrent()

            assertEquals(genuine, strategy.lastWorking.value)
            assertEquals(listOf(impostor, genuine), connector.calls)
        }

    private fun TestScope.newStrategy(
        connector: FakeConnector,
        bonjour: () -> List<CandidateAddress>,
        pairing: () -> List<CandidateAddress>,
        initialLastWorking: CandidateAddress? = null,
    ): ReconnectStrategy =
        ReconnectStrategy(
            connector = connector,
            bonjourSource = BonjourCandidateSource { bonjour() },
            pairingAddressSource = PairingAddressSource { pairing() },
            dispatcher = StandardTestDispatcher(testScheduler),
            initialLastWorking = initialLastWorking,
        )

    private class FakeConnector(
        val result: (CandidateAddress) -> ConnectResult,
    ) : Connector {
        val calls = mutableListOf<CandidateAddress>()

        override suspend fun connect(candidate: CandidateAddress): ConnectResult {
            calls += candidate
            return result(candidate)
        }
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1000L
        const val SEQUENCE_LENGTH = 7
        const val SUCCESS_ON_CYCLE = 3
    }
}
