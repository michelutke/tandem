package dev.tandem.feature.status

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.deviceStatus
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/**
 * StatusPublisher tests (E23-03; `docs/planning/backlog/phase-2.yaml` E23-03's `tdd:` list).
 * [FakeTandemSession] scripts connection state via `emitState` and records sends via
 * `sentFrames`; a [MutableSharedFlow] stands in for `StatusAggregator.status` so each test drives
 * exactly the changes and timing it needs; [TestClock] ties the 60 s throttle window to the same
 * `testScheduler` the `StandardTestDispatcher` uses (E00-18).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StatusPublisherTest {
    @Test
    fun statusThrottle_firstChange_sentImmediately() =
        runTest {
            val session = FakeTandemSession()
            val statusFlow = newStatusFlow()
            newPublisher(statusFlow, session)
            runCurrent() // lets the collector attach before the flow ever emits

            statusFlow.emit(status(50))
            runCurrent()

            assertEquals(listOf(50), sentLevels(session))
        }

    @Test
    fun statusThrottle_secondChangeAt10s_sentAt60sWithLatestValues() =
        runTest {
            val session = FakeTandemSession()
            val statusFlow = newStatusFlow()
            newPublisher(statusFlow, session)
            runCurrent() // lets the collector attach before the flow ever emits

            statusFlow.emit(status(10))
            runCurrent()
            assertEquals(listOf(10), sentLevels(session))

            advanceTimeBy(10.seconds)
            statusFlow.emit(status(20))
            runCurrent()
            assertEquals(listOf(10), sentLevels(session))

            // A later change within the same coalescing window: only the latest value is sent.
            advanceTimeBy(30.seconds)
            statusFlow.emit(status(30))
            runCurrent()
            assertEquals(listOf(10), sentLevels(session))

            advanceTimeBy(20.seconds) // t=60s
            runCurrent()
            assertEquals(listOf(10, 30), sentLevels(session))
        }

    @Test
    fun statusThrottle_noChangeFor10min_zeroSends() =
        runTest {
            val session = FakeTandemSession()
            val statusFlow = newStatusFlow()
            newPublisher(statusFlow, session)

            advanceTimeBy(10.minutes)
            runCurrent()

            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun statusThrottle_changeAt61sAfterLastSend_sentImmediately() =
        runTest {
            val session = FakeTandemSession()
            val statusFlow = newStatusFlow()
            newPublisher(statusFlow, session)
            runCurrent() // lets the collector attach before the flow ever emits

            statusFlow.emit(status(1))
            runCurrent()
            assertEquals(listOf(1), sentLevels(session))

            advanceTimeBy(61.seconds)
            statusFlow.emit(status(2))
            runCurrent()

            assertEquals(listOf(1, 2), sentLevels(session))
        }

    @Test
    fun statusThrottle_sessionReady_currentStatusSentImmediately() =
        runTest {
            val session = FakeTandemSession()
            val statusFlow = newStatusFlow()
            newPublisher(statusFlow, session)
            runCurrent() // lets the collector attach before the flow ever emits

            statusFlow.emit(status(10))
            runCurrent()
            assertEquals(listOf(10), sentLevels(session))

            // Inside the throttle window: coalesced, not yet sent.
            advanceTimeBy(10.seconds)
            statusFlow.emit(status(20))
            runCurrent()
            assertEquals(listOf(10), sentLevels(session))

            session.emitState(ConnectionState.Ready(connectedAt = Instant.EPOCH))
            runCurrent()
            assertEquals(listOf(10, 20), sentLevels(session))

            // The coalesced send this bypassed must not fire again at its original t=60s deadline.
            advanceTimeBy(50.seconds)
            runCurrent()
            assertEquals(listOf(10, 20), sentLevels(session))
        }

    private fun TestScope.newStatusFlow(): MutableSharedFlow<DeviceStatus> =
        MutableSharedFlow(extraBufferCapacity = EXTRA_BUFFER_CAPACITY)

    private fun TestScope.newPublisher(
        statusFlow: MutableSharedFlow<DeviceStatus>,
        session: FakeTandemSession,
    ): StatusPublisher =
        StatusPublisher(
            status = statusFlow,
            session = session,
            clock = TestClock(testScheduler),
            dispatcher = StandardTestDispatcher(testScheduler),
        )

    private fun status(batteryLevel: Int): DeviceStatus =
        deviceStatus {
            this.batteryLevel = batteryLevel
        }

    private fun sentLevels(session: FakeTandemSession): List<Int> =
        session.sentFrames.filter { it.channel == Channel.CHANNEL_STATUS }.map { it.deviceStatus.batteryLevel }

    private companion object {
        const val EXTRA_BUFFER_CAPACITY = 10
    }
}
