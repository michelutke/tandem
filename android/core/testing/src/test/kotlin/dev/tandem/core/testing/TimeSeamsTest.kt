package dev.tandem.core.testing

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.extension.ExtensionContext
import java.lang.reflect.Proxy
import java.time.Duration
import kotlin.time.Duration.Companion.seconds

@OptIn(ExperimentalCoroutinesApi::class)
class TimeSeamsTest {
    @Test
    fun testClock_advanceTimeBy15s_instantAdvancesBy15s() =
        runTest {
            val clock = TestClock(testScheduler)
            val before = clock.instant()

            advanceTimeBy(15.seconds)

            assertEquals(Duration.ofSeconds(15), Duration.between(before, clock.instant()))
        }

    @Test
    fun fakeElapsedRealtime_advanceTimeBy45s_readingAdvancesBy45000ms() =
        runTest {
            val elapsed = FakeElapsedRealtime(testScheduler)
            val before = elapsed.elapsedRealtimeMillis()

            advanceTimeBy(45.seconds)

            assertEquals(45_000L, elapsed.elapsedRealtimeMillis() - before)
        }

    @Test
    fun delayInTestScope_advanceTimeBy120s_completesWithoutRealWait() {
        val realStart = System.nanoTime()
        runTest {
            var expired = false
            launch {
                delay(120.seconds)
                expired = true
            }
            advanceTimeBy(119.seconds)
            runCurrent()
            assertFalse(expired)
            advanceTimeBy(1.seconds)
            runCurrent()
            assertTrue(expired)
        }
        assertTrue(System.nanoTime() - realStart < 1_000_000_000L, "a 120 s virtual timer must take < 1 s real time")
    }

    @Test
    fun mainDispatcherExtension_afterEach_resetsMainDispatcher() {
        val dispatcher = StandardTestDispatcher()
        val extension = MainDispatcherExtension(dispatcher)
        val context =
            Proxy.newProxyInstance(javaClass.classLoader, arrayOf(ExtensionContext::class.java)) { _, _, _ -> null }
                as ExtensionContext

        extension.beforeEach(context)
        var ranOnTestDispatcher = false
        runTest(dispatcher) { withContext(Dispatchers.Main) { ranOnTestDispatcher = true } }
        extension.afterEach(context)

        assertTrue(ranOnTestDispatcher)
        val mainAfterReset = runCatching { Dispatchers.Main.isDispatchNeeded(kotlin.coroutines.EmptyCoroutineContext) }
        assertTrue(mainAfterReset.isFailure, "Dispatchers.Main should be unset again after afterEach")
    }
}
