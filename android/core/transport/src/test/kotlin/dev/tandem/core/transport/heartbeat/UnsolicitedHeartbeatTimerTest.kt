package dev.tandem.core.transport.heartbeat

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/**
 * [UnsolicitedHeartbeatTimer] tests (E20-15; `docs/planning/backlog/phase-2.yaml` E20-15's `tdd:`
 * list). Every test shares its `runTest` scope's `StandardTestDispatcher`, so the 15 s idle-send
 * delay advances in virtual time (E00-18).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class UnsolicitedHeartbeatTimerTest {
    @Test
    fun unsolicitedTimer_interactive15sWithoutSend_sendsHeartbeat() =
        runTest {
            var sendCount = 0
            val timer =
                UnsolicitedHeartbeatTimer(
                    sent = MutableSharedFlow(),
                    isIdle = MutableStateFlow(false),
                    sendHeartbeat = { sendCount++ },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            timer.start()

            advanceTimeBy(15.seconds)
            runCurrent()

            assertEquals(1, sendCount)
        }

    @Test
    fun unsolicitedTimer_deviceIdleMode_noHeartbeatScheduled() =
        runTest {
            var sendCount = 0
            val timer =
                UnsolicitedHeartbeatTimer(
                    sent = MutableSharedFlow(),
                    isIdle = MutableStateFlow(true),
                    sendHeartbeat = { sendCount++ },
                    dispatcher = StandardTestDispatcher(testScheduler),
                )
            timer.start()

            advanceTimeBy(10.minutes)
            runCurrent()

            assertEquals(0, sendCount)
        }
}
