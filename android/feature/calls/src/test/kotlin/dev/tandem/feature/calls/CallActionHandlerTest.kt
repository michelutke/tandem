package dev.tandem.feature.calls

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.CallActionErrorCode
import dev.tandem.protocol.v1.CallActionType
import dev.tandem.protocol.v1.CallDirection
import dev.tandem.protocol.v1.CallState
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.callAction
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** CallActionHandler tests (E52-04; `docs/planning/backlog/phase-5.yaml` E52-04's `tdd:` list). */
class CallActionHandlerTest {
    private val gateway = FakeCallGateway()
    private val permissions = FakeCallPermissions()
    private val tracker = CallTracker()
    private val session = FakeTandemSession()

    private fun TestScope.handler() =
        CallActionHandler(gateway, permissions, tracker, session, StandardTestDispatcher(testScheduler))

    private fun track(state: CallState) {
        tracker.current = TrackedCall("call-1", CallDirection.CALL_DIRECTION_INCOMING, state)
    }

    private suspend fun CallActionHandler.act(
        type: CallActionType,
        id: String = "call-1",
    ) = handle(
        callAction {
            requestId = "req-1"
            callId = id
            action = type
        },
    )

    private val result get() = session.sentFrames.single().callActionResult

    @Test
    fun callActionHandler_answerWhileRinging_invokesAcceptOnce() =
        runTest {
            track(CallState.CALL_STATE_RINGING)

            handler().act(CallActionType.CALL_ACTION_TYPE_ANSWER)

            assertEquals(1, gateway.acceptCalls)
            assertTrue(result.success)
            assertEquals("req-1", result.requestId)
            assertEquals(Channel.CHANNEL_CALLS, session.sentFrames.single().channel)
        }

    @Test
    fun callActionHandler_answerNotRinging_returnsNotRinging() =
        runTest {
            track(CallState.CALL_STATE_ACTIVE)

            handler().act(CallActionType.CALL_ACTION_TYPE_ANSWER)

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_NOT_RINGING, result.errorCode)
            assertFalse(result.success)
            assertEquals(0, gateway.acceptCalls)
        }

    @Test
    fun callActionHandler_declineWhileRinging_endsCallWithoutAccept() =
        runTest {
            track(CallState.CALL_STATE_RINGING)

            handler().act(CallActionType.CALL_ACTION_TYPE_DECLINE)

            assertEquals(1, gateway.endCalls)
            assertEquals(0, gateway.acceptCalls)
            assertTrue(result.success)
        }

    @Test
    fun callActionHandler_hangupNoActiveCall_returnsNoActiveCall() =
        runTest {
            track(CallState.CALL_STATE_ACTIVE)
            tracker.end()

            handler().act(CallActionType.CALL_ACTION_TYPE_HANGUP)

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL, result.errorCode)
            assertEquals(0, gateway.endCalls)
        }

    @Test
    fun callActionHandler_hangupActiveCall_endsCall() =
        runTest {
            track(CallState.CALL_STATE_ACTIVE)

            handler().act(CallActionType.CALL_ACTION_TYPE_HANGUP)

            assertEquals(1, gateway.endCalls)
            assertTrue(result.success)
            assertEquals("call-1", result.callId)
        }

    @Test
    fun callActionHandler_unknownCallId_returnsUnknownCall() =
        runTest {
            track(CallState.CALL_STATE_RINGING)

            handler().act(CallActionType.CALL_ACTION_TYPE_ANSWER, id = "stale")

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNKNOWN_CALL, result.errorCode)
            assertEquals("", result.callId)
            assertEquals(0, gateway.acceptCalls)
        }

    @Test
    fun callActionHandler_answerPhoneCallsDenied_returnsPermissionDenied() =
        runTest {
            track(CallState.CALL_STATE_RINGING)
            permissions.answerPhoneCalls = false

            handler().act(CallActionType.CALL_ACTION_TYPE_ANSWER)

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_PERMISSION_DENIED, result.errorCode)
            assertEquals(0, gateway.acceptCalls)
            assertEquals(0, gateway.endCalls)
        }

    @Test
    fun callActionHandler_platformEndedNothing_returnsNoActiveCall() =
        runTest {
            track(CallState.CALL_STATE_ACTIVE)
            gateway.endResult = false

            handler().act(CallActionType.CALL_ACTION_TYPE_HANGUP)

            assertEquals(CallActionErrorCode.CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL, result.errorCode)
        }

    @Test
    fun callActionHandler_actionArrivesOnCallsChannel_answersIt() =
        runTest {
            track(CallState.CALL_STATE_RINGING)
            val handler = handler()
            backgroundScope.launch { handler.run() }
            runCurrent()

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CALLS
                    callAction =
                        callAction {
                            requestId = "req-9"
                            callId = "call-1"
                            action = CallActionType.CALL_ACTION_TYPE_ANSWER
                        }
                },
            )
            runCurrent()

            assertEquals(1, gateway.acceptCalls)
            assertEquals("req-9", result.requestId)
        }
}
