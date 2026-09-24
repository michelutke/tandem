package dev.tandem.core.testing

import kotlinx.coroutines.test.TestCoroutineScheduler
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * A [Clock] whose instant follows [TestCoroutineScheduler.currentTime], so `advanceTimeBy`
 * moves wall time and pending `delay`s together (E00-18).
 */
class TestClock(
    private val scheduler: TestCoroutineScheduler,
    private val epoch: Instant = Instant.EPOCH,
    private val zone: ZoneId = ZoneOffset.UTC,
) : Clock() {
    override fun instant(): Instant = epoch.plusMillis(scheduler.currentTime)

    override fun getZone(): ZoneId = zone

    override fun withZone(zone: ZoneId): Clock = TestClock(scheduler, epoch, zone)
}
