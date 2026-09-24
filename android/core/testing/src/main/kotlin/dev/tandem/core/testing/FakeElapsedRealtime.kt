package dev.tandem.core.testing

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import kotlinx.coroutines.test.TestCoroutineScheduler

/** [ElapsedRealtimeSource] whose reading follows [TestCoroutineScheduler.currentTime] (E00-18). */
class FakeElapsedRealtime(
    private val scheduler: TestCoroutineScheduler,
    private val bootOffsetMillis: Long = 0,
) : ElapsedRealtimeSource {
    override fun elapsedRealtimeMillis(): Long = bootOffsetMillis + scheduler.currentTime
}
