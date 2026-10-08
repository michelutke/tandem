package dev.tandem.app.home

import dev.tandem.feature.files.TransferActivity
import dev.tandem.feature.files.TransferBatchAggregator
import dev.tandem.feature.files.TransferBytes
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TransferHomeRingStateSourceTest {
    private val idleState = HomeRingState.Idle(itemsSyncedToday = 26, sevenDayAverage = 30)
    private val activity = MutableStateFlow(TransferActivity())

    private fun TestScope.source() =
        TransferHomeRingStateSource(
            FakeHomeRingStateSource(idleState),
            activity,
            backgroundScope,
            doneMillis = 1_500,
        ).also { runCurrent() }

    private fun bytes(
        done: Long,
        total: Long,
    ) = TransferBytes(done, total)

    @Test
    fun ringState_noTransfer_isIdle() =
        runTest(StandardTestDispatcher()) {
            assertEquals(idleState, source().state.value)
        }

    @Test
    fun ringState_sendingHalf_showsPercentToMac() =
        runTest(StandardTestDispatcher()) {
            val source = source()

            activity.value = TransferActivity(sending = bytes(42, 100))
            runCurrent()

            assertEquals(HomeRingState.Transfer(percent = 42, toMac = true), source.state.value)
        }

    @Test
    fun ringState_receivingSeveralFiles_aggregatesBytes() =
        runTest(StandardTestDispatcher()) {
            val source = source()

            activity.value =
                TransferBatchAggregator().update(emptyMap(), mapOf("a" to bytes(50, 100), "b" to bytes(0, 100)))
            runCurrent()

            assertEquals(HomeRingState.Transfer(percent = 25, toMac = false), source.state.value)
        }

    @Test
    fun ringState_transferEnds_showsDoneThenIdleAfterPause() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            activity.value = TransferActivity(sending = bytes(100, 100))
            runCurrent()

            activity.value = TransferActivity()
            runCurrent()
            assertEquals(HomeRingState.TransferDone(toMac = true), source.state.value)

            advanceTimeBy(1_499)
            runCurrent()
            assertEquals(HomeRingState.TransferDone(toMac = true), source.state.value)
            advanceTimeBy(1)
            runCurrent()
            assertEquals(idleState, source.state.value)
        }

    @Test
    fun ringState_newTransferDuringDone_replacesDoneAndKeepsItAfterOldTimer() =
        runTest(StandardTestDispatcher()) {
            val source = source()
            activity.value = TransferActivity(sending = bytes(100, 100))
            runCurrent()
            activity.value = TransferActivity()
            runCurrent()
            advanceTimeBy(1_000)

            activity.value = TransferActivity(receiving = bytes(10, 100))
            runCurrent()
            advanceTimeBy(1_000)
            runCurrent()

            assertEquals(HomeRingState.Transfer(percent = 10, toMac = false), source.state.value)
        }
}
