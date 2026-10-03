package dev.tandem.feature.files

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// E40-12 tdd:
//   unit: androidProgressVm_threeMiBInThreeSeconds_reportsOneMiBPerSecond
//   unit: androidProgressVm_bytesFlowing_emitsBetween250msAnd1s
@OptIn(ExperimentalCoroutinesApi::class)
class TransferProgressViewModelTest {
    private val mib = 1024L * 1024

    @Test
    fun androidProgressVm_threeMiBInThreeSeconds_reportsOneMiBPerSecond() =
        runTest {
            val source = MutableStateFlow(mapOf("t" to TransferBytes(0, 3 * mib)))
            val vm = TransferProgressViewModel(source, TestClock(testScheduler), backgroundScope)

            repeat(12) { step ->
                source.value = mapOf("t" to TransferBytes((step + 1) * mib / 4, 3 * mib))
                advanceTimeBy(250)
                runCurrent()
            }

            val progress = vm.progress.value.getValue("t")
            assertEquals(100, progress.percent)
            assertTrue(progress.bytesPerSecond in (mib * 99 / 100)..(mib * 101 / 100)) { "${progress.bytesPerSecond}" }
        }

    @Test
    fun androidProgressVm_bytesFlowing_emitsBetween250msAnd1s() =
        runTest {
            val source = MutableStateFlow(mapOf("t" to TransferBytes(0, 100 * mib)))
            val vm = TransferProgressViewModel(source, TestClock(testScheduler), backgroundScope)
            val emissionTimes = mutableListOf<Long>()
            backgroundScope.launch {
                vm.progress.collect {
                    if (it.isNotEmpty()) {
                        emissionTimes +=
                            testScheduler.currentTime
                    }
                }
            }

            repeat(16) { step ->
                source.value = mapOf("t" to TransferBytes((step + 1) * mib, 100 * mib))
                advanceTimeBy(250)
                runCurrent()
            }

            val gaps = emissionTimes.zipWithNext { a, b -> b - a }
            assertTrue(gaps.isNotEmpty())
            assertTrue(gaps.all { it in 250..1000 }) { "$gaps" }
        }
}
