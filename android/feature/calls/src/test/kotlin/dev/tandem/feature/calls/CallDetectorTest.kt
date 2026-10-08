package dev.tandem.feature.calls

import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.CallDirection
import dev.tandem.protocol.v1.CallState
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/** CallDetector tests (E52-03; `docs/planning/backlog/phase-5.yaml` E52-03's `tdd:` list). */
@OptIn(ExperimentalCoroutinesApi::class)
class CallDetectorTest {
    private val gateway = FakeCallGateway()
    private val session = FakeTandemSession()
    private val tracker = CallTracker()
    private val logLines = mutableListOf<String>()
    private val endedDurations = mutableListOf<Long?>()
    private var nextId = 0

    private fun TestScope.start(permissions: FakeCallPermissions = FakeCallPermissions()) {
        val detector =
            CallDetector(
                gateway,
                permissions,
                session,
                tracker,
                normalize = { if (it == "079 123 45 67") "+41791234567" else null },
                clock = TestClock(testScheduler, Instant.parse("2026-10-08T10:00:00Z")),
                newCallId = { "call-${nextId++}" },
                onEnded = { endedDurations += it },
                log = { logLines += it },
            )
        backgroundScope.launch(StandardTestDispatcher(testScheduler)) { detector.run() }
        runCurrent()
    }

    private fun TestScope.emit(
        state: PhoneCallState,
        number: String? = null,
    ) {
        gateway.emit(state, number)
        runCurrent()
    }

    private val events get() = session.sentFrames.map { it.callEvent }

    @Test
    fun callDetector_ringingChange_sendsIncomingRingingEventImmediately() =
        runTest {
            start()
            emit(PhoneCallState.Idle)
            val before = currentTime
            emit(PhoneCallState.Ringing, "079 123 45 67")

            val event = events.single()
            assertEquals(Channel.CHANNEL_CALLS, session.sentFrames.single().channel)
            assertEquals(CallDirection.CALL_DIRECTION_INCOMING, event.direction)
            assertEquals(CallState.CALL_STATE_RINGING, event.state)
            assertEquals("+41791234567", event.normalizedE164)
            assertEquals(before, currentTime)
        }

    @Test
    fun callDetector_ringingOffhookIdle_sendsRingingActiveEndedSameCallId() =
        runTest {
            start()
            emit(PhoneCallState.Idle)
            emit(PhoneCallState.Ringing, "079 123 45 67")
            emit(PhoneCallState.OffHook)
            emit(PhoneCallState.Idle)

            assertEquals(
                listOf(CallState.CALL_STATE_RINGING, CallState.CALL_STATE_ACTIVE, CallState.CALL_STATE_ENDED),
                events.map { it.state },
            )
            assertEquals(1, events.map { it.callId }.toSet().size)
            assertEquals(listOf("079 123 45 67"), events.map { it.address }.toSet().toList())
        }

    @Test
    fun callDetector_idleToOffhook_sendsOutgoingDialingEvent() =
        runTest {
            start()
            emit(PhoneCallState.Idle)
            emit(PhoneCallState.Ringing, "079 123 45 67")
            emit(PhoneCallState.Idle)
            emit(PhoneCallState.OffHook)

            val dialing = events.last()
            assertEquals(CallDirection.CALL_DIRECTION_OUTGOING, dialing.direction)
            assertEquals(CallState.CALL_STATE_DIALING, dialing.state)
            assertNotEquals(events.first().callId, dialing.callId)
        }

    @Test
    fun callDetector_readPhoneStateDenied_registersNoCallback() =
        runTest {
            start(FakeCallPermissions(readPhoneState = false))
            emit(PhoneCallState.Ringing, "079 123 45 67")

            assertEquals(0, gateway.collectorCount)
            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun callDetector_ringingChange_logLinesOmitIncomingNumber() =
        runTest {
            start()
            emit(PhoneCallState.Idle)
            emit(PhoneCallState.Ringing, "079 123 45 67")
            emit(PhoneCallState.OffHook)
            emit(PhoneCallState.Idle)

            assertTrue(logLines.isNotEmpty())
            assertFalse(logLines.any { it.contains("079") || it.contains("4179") })
        }

    @Test
    fun callDetector_firstEmissionOffhook_reportsNothingForCallAlreadyInProgress() =
        runTest {
            start()
            emit(PhoneCallState.OffHook)
            emit(PhoneCallState.Idle)

            assertTrue(session.sentFrames.isEmpty())
            assertEquals(emptyList<Long?>(), endedDurations)
        }

    @Test
    fun callDetector_answeredCallEnds_reportsTalkTimeToOnEnded() =
        runTest {
            start()
            emit(PhoneCallState.Idle)
            emit(PhoneCallState.Ringing)
            emit(PhoneCallState.OffHook)
            advanceTimeBy(42_000)
            emit(PhoneCallState.Idle)

            assertEquals(listOf<Long?>(42L), endedDurations)
        }
}
