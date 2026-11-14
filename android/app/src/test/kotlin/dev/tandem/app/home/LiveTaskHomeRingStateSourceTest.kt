package dev.tandem.app.home

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.seconds

@OptIn(ExperimentalCoroutinesApi::class)
class LiveTaskHomeRingStateSourceTest {
    private val idle = HomeRingState.Idle(itemsSyncedToday = 5, sevenDayAverage = 10)
    private val reconnect = MutableStateFlow<ReconnectProgress?>(null)
    private val mirroring = MutableStateFlow(false)
    private val ringing = MutableStateFlow(false)

    private fun TestScope.source(): LiveTaskHomeRingStateSource {
        val elapsed = ElapsedRealtimeSource { testScheduler.currentTime }
        return LiveTaskHomeRingStateSource(
            FakeHomeRingStateSource(idle),
            reconnect,
            mirroring,
            ringing,
            elapsed,
            backgroundScope,
        ).also { runCurrent() }
    }

    @Test
    fun ringState_nothingRunning_isBase() =
        runTest(StandardTestDispatcher()) {
            assertEquals(idle, source().state.value)
        }

    @Test
    fun ringState_reconnectWaiting_showsSecondsAndNextAttempt() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            reconnect.value = ReconnectProgress(failedCycles = 2, wait = 4.seconds)
            runCurrent()
            assertEquals(HomeRingState.Reconnecting(4, 4), source.state.value)
            advanceTimeBy(1_000)
            runCurrent()
            assertEquals(HomeRingState.Reconnecting(3, 4), source.state.value)
        }

    @Test
    fun ringState_reconnectBackToConnected_returnsToBase() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            reconnect.value = ReconnectProgress(failedCycles = 1, wait = 2.seconds)
            runCurrent()
            reconnect.value = null
            runCurrent()
            assertEquals(idle, source.state.value)
        }

    @Test
    fun ringState_firstCycleNotFailedYet_isBase() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            reconnect.value = ReconnectProgress(failedCycles = 0, wait = null)
            runCurrent()
            assertEquals(idle, source.state.value)
        }

    @Test
    fun ringState_ringing_isRinging() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            ringing.value = true
            runCurrent()
            assertEquals(HomeRingState.Ringing, source.state.value)
        }

    @Test
    fun ringState_mirroring_countsElapsedSeconds() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            mirroring.value = true
            runCurrent()
            assertEquals(HomeRingState.Mirroring(0), source.state.value)
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(HomeRingState.Mirroring(3), source.state.value)
            mirroring.value = false
            runCurrent()
            assertEquals(idle, source.state.value)
        }
}
