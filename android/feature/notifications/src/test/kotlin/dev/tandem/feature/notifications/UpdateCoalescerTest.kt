package dev.tandem.feature.notifications

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.milliseconds

/**
 * UpdateCoalescer tests (E30-12; `docs/planning/backlog/phase-3.yaml` E30-12's `tdd:` list).
 * [TestClock] ties the 500 ms rate-limit window to the same `testScheduler` the
 * `StandardTestDispatcher` uses (E00-18), so every test drives virtual time instead of sleeping.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class UpdateCoalescerTest {
    @Test
    fun updateCoalescer_tenUpdatesIn1sSameKey_atMostThreeForwardedEndingWithTenth() =
        runTest {
            val sent = mutableListOf<Int>()
            val coalescer = newCoalescer(sent)

            repeat(TEN_UPDATES) { i ->
                coalescer.update("key", i + 1)
                runCurrent()
                advanceTimeBy(UPDATE_SPACING_MS.milliseconds)
            }
            runCurrent()

            assertTrue(sent.size <= MAX_FORWARDED, "expected at most $MAX_FORWARDED forwards, got $sent")
            assertEquals(TEN_UPDATES, sent.last())
        }

    @Test
    fun updateCoalescer_singleUpdate_forwardedAtVirtualTimeZero() =
        runTest {
            val sent = mutableListOf<Int>()
            val coalescer = newCoalescer(sent)

            coalescer.update("key", 1)
            runCurrent()

            assertEquals(listOf(1), sent)
            assertEquals(0L, testScheduler.currentTime)
        }

    @Test
    fun updateCoalescer_twoKeysInterleaved_eachKeyLimitedIndependently() =
        runTest {
            val sent = mutableListOf<Pair<String, Int>>()
            val coalescer =
                UpdateCoalescer<String, Pair<String, Int>>(
                    forward = { sent.add(it) },
                    clock = TestClock(testScheduler),
                    dispatcher = StandardTestDispatcher(testScheduler),
                )

            coalescer.update("a", "a" to 1)
            coalescer.update("b", "b" to 1)
            runCurrent()
            assertEquals(listOf("a" to 1, "b" to 1), sent)

            // Within the window: both keys coalesce independently.
            advanceTimeBy(WINDOW_MS.milliseconds / 2)
            coalescer.update("a", "a" to 2)
            coalescer.update("b", "b" to 2)
            runCurrent()
            assertEquals(listOf("a" to 1, "b" to 1), sent)

            advanceTimeBy(WINDOW_MS.milliseconds)
            runCurrent()
            assertEquals(listOf("a" to 1, "b" to 1, "a" to 2, "b" to 2), sent)
        }

    @Test
    fun updateCoalescer_pendingUpdateThenRemoved_pendingNeverSent() =
        runTest {
            val sent = mutableListOf<Int>()
            val coalescer = newCoalescer(sent)

            coalescer.update("key", 1)
            runCurrent()
            assertEquals(listOf(1), sent)

            advanceTimeBy((WINDOW_MS / 2).milliseconds)
            coalescer.update("key", 2)
            runCurrent()
            assertEquals(listOf(1), sent) // coalesced, not yet forwarded

            coalescer.remove("key")
            advanceTimeBy(WINDOW_MS.milliseconds)
            runCurrent()

            assertEquals(listOf(1), sent) // update 2 never forwarded
        }

    private fun TestScope.newCoalescer(sent: MutableList<Int>): UpdateCoalescer<String, Int> =
        UpdateCoalescer(
            forward = { sent.add(it) },
            clock = TestClock(testScheduler),
            dispatcher = StandardTestDispatcher(testScheduler),
        )

    private companion object {
        const val TEN_UPDATES = 10
        const val MAX_FORWARDED = 3
        const val UPDATE_SPACING_MS = 100L
        const val WINDOW_MS = 500L
    }
}
