package dev.tandem.feature.calls

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.CallAction
import dev.tandem.protocol.v1.CallActionErrorCode
import dev.tandem.protocol.v1.CallActionType
import dev.tandem.protocol.v1.CallState
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.callActionResult
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.withContext

/**
 * E52-04 phone side of the Mac's `CallAction`s (PRD F-8.4, docs/protocol/SPEC.md #calls-channel
 * "Call actions"): ANSWER accepts the ringing call, DECLINE ends it without accepting, HANGUP ends a
 * dialling or active call, all through [gateway] and all requiring ANSWER_PHONE_CALLS (denied
 * answers PERMISSION_DENIED without touching [gateway]). Exactly one `CallActionResult` echoing the
 * request id is sent per action. Audio stays on the phone. [log] receives result names only, never
 * numbers (invariant 7).
 */
class CallActionHandler(
    private val gateway: CallGateway,
    private val permissions: CallPermissions,
    private val tracker: CallTracker,
    private val session: TandemSession,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: (String) -> Unit = {},
) {
    suspend fun run() {
        session
            .receive(Channel.CHANNEL_CALLS)
            .filter { it.hasCallAction() }
            .collect { handle(it.callAction) }
    }

    suspend fun handle(action: CallAction) {
        val error = withContext(ioDispatcher) { perform(action) }
        log("call_action action=${action.action.name} error=${error.name}")
        val succeeded = error == CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED
        session.send(Channel.CHANNEL_CALLS) {
            callActionResult =
                callActionResult {
                    requestId = action.requestId
                    callId = if (succeeded) action.callId else ""
                    success = succeeded
                    errorCode = error
                }
        }
    }

    private fun perform(action: CallAction): CallActionErrorCode {
        if (!permissions.answerPhoneCalls()) return CallActionErrorCode.CALL_ACTION_ERROR_CODE_PERMISSION_DENIED
        val call = tracker.current?.takeIf { it.callId == action.callId }
        return when {
            call == null -> missingCallError(action)
            action.action == CallActionType.CALL_ACTION_TYPE_ANSWER -> answer(call)
            action.action == CallActionType.CALL_ACTION_TYPE_DECLINE -> decline(call)
            action.action == CallActionType.CALL_ACTION_TYPE_HANGUP -> hangUp(call)
            else -> CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNKNOWN_CALL
        }
    }

    private fun missingCallError(action: CallAction): CallActionErrorCode =
        when {
            action.callId != tracker.lastEndedCallId -> {
                CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNKNOWN_CALL
            }

            action.action == CallActionType.CALL_ACTION_TYPE_HANGUP -> {
                CallActionErrorCode.CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL
            }

            else -> {
                CallActionErrorCode.CALL_ACTION_ERROR_CODE_NOT_RINGING
            }
        }

    private fun answer(call: TrackedCall): CallActionErrorCode {
        if (call.state != CallState.CALL_STATE_RINGING) return CallActionErrorCode.CALL_ACTION_ERROR_CODE_NOT_RINGING
        return guarded { gateway.acceptRingingCall() }
    }

    private fun decline(call: TrackedCall): CallActionErrorCode {
        if (call.state != CallState.CALL_STATE_RINGING) return CallActionErrorCode.CALL_ACTION_ERROR_CODE_NOT_RINGING
        return endCall(CallActionErrorCode.CALL_ACTION_ERROR_CODE_NOT_RINGING)
    }

    private fun hangUp(call: TrackedCall): CallActionErrorCode {
        if (call.state != CallState.CALL_STATE_DIALING && call.state != CallState.CALL_STATE_ACTIVE) {
            return CallActionErrorCode.CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL
        }
        return endCall(CallActionErrorCode.CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL)
    }

    private fun endCall(ifNothingEnded: CallActionErrorCode): CallActionErrorCode {
        var ended = false
        val error = guarded { ended = gateway.endCall() }
        return if (error == CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED && !ended) ifNothingEnded else error
    }

    private inline fun guarded(block: () -> Unit): CallActionErrorCode =
        try {
            block()
            CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED
        } catch (_: SecurityException) {
            CallActionErrorCode.CALL_ACTION_ERROR_CODE_PERMISSION_DENIED
        }
}
