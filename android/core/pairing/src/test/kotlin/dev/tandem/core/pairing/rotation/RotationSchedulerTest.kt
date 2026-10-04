package dev.tandem.core.pairing.rotation

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Duration
import java.time.Instant

private val INTERVAL = Duration.ofDays(365)
private val ONE_DAY = Duration.ofDays(1)

@OptIn(ExperimentalCoroutinesApi::class)
class RotationSchedulerTest {
    private class Env(
        scope: TestScope,
        val store: NextRotationDueStore,
        connected: Boolean = true,
    ) {
        val clock = TestClock(scope.testScheduler)
        val authenticated = MutableStateFlow(connected)
        var rotations = 0
        var outcome: RotationOutcome = RotationOutcome.Committed

        val scheduler =
            RotationScheduler(clock, INTERVAL, store, authenticated) {
                rotations++
                outcome
            }
    }

    private class MemoryStore(
        var due: Instant? = null,
    ) : NextRotationDueStore {
        override fun get() = due

        override fun set(due: Instant) {
            this.due = due
        }
    }

    private fun TestScope.advanceBy(duration: Duration) {
        advanceTimeBy(duration.toMillis())
        runCurrent()
    }

    @Test
    fun androidScheduledRotation_oneDayBeforeDue_noRotationStarted() =
        runTest {
            val env = Env(this, MemoryStore())
            val job = launch { env.scheduler.run() }
            runCurrent()

            advanceBy(INTERVAL.minus(ONE_DAY))

            assertEquals(0, env.rotations)
            job.cancel()
        }

    @Test
    fun androidScheduledRotation_dueWhileConnected_rotationStartedOnce() =
        runTest {
            val env = Env(this, MemoryStore())
            env.outcome = RotationOutcome.TimedOut
            val job = launch { env.scheduler.run() }
            runCurrent()

            advanceBy(INTERVAL.plus(ONE_DAY))

            assertEquals(1, env.rotations)
            job.cancel()
        }

    @Test
    fun androidScheduledRotation_dueWhileOffline_startedOnNextAuthenticatedSession() =
        runTest {
            val env = Env(this, MemoryStore(), connected = false)
            env.store.set(env.clock.instant().plus(ONE_DAY))
            val job = launch { env.scheduler.run() }
            runCurrent()

            advanceBy(ONE_DAY.multipliedBy(3))
            assertEquals(0, env.rotations)

            env.authenticated.value = true
            runCurrent()

            assertEquals(1, env.rotations)
            job.cancel()
        }

    @Test
    fun androidScheduledRotation_afterSuccess_nextDueIsNowPlusInterval() =
        runTest {
            val env = Env(this, MemoryStore())
            val job = launch { env.scheduler.run() }
            runCurrent()

            advanceBy(INTERVAL.plus(ONE_DAY))

            assertEquals(1, env.rotations)
            val dueAt = env.clock.instant() - ONE_DAY + INTERVAL
            assertEquals(dueAt, env.store.get())
            job.cancel()
        }

    @Test
    fun androidScheduledRotation_processRestart_persistedDueHonoured(
        @TempDir dir: File,
    ) = runTest {
        val file = File(dir, "next-rotation-due")
        val first = Env(this, FileNextRotationDueStore(file))
        val firstJob = launch { first.scheduler.run() }
        runCurrent()
        advanceBy(INTERVAL.minus(ONE_DAY))
        firstJob.cancel()

        val restarted = Env(this, FileNextRotationDueStore(file))
        val restartedJob = launch { restarted.scheduler.run() }
        runCurrent()
        assertEquals(0, restarted.rotations)

        advanceBy(ONE_DAY.plus(Duration.ofMinutes(1)))

        assertEquals(1, restarted.rotations)
        restartedJob.cancel()
    }
}
