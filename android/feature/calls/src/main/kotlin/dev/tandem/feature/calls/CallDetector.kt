package dev.tandem.feature.calls

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.CallDirection
import dev.tandem.protocol.v1.CallState
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.callEvent
import java.time.Clock
import java.util.UUID

/**
 * E52-03 phone side of call detection (PRD F-8.4, docs/protocol/SPEC.md #calls-channel): maps
 * [CallGateway.callStates] to `CallEvent`s on the CALLS channel, sent immediately without debounce.
 * RINGING starts an incoming call, OFFHOOK moves it to ACTIVE, IDLE ends it; IDLE then OFFHOOK is an
 * outgoing DIALING call (the platform cannot tell dialling from connected, so an outgoing call stays
 * DIALING until it ends). The first platform emission only seeds state: an OFFHOOK there is a call
 * already in progress that this session never saw start, so it is not reported. Without
 * READ_PHONE_STATE nothing registers and nothing is sent. [log] receives state names only, never
 * numbers (invariant 7). [onEnded] gets the talk time in seconds of a call that became ACTIVE.
 */
@Suppress("LongParameterList") // independent injected seams: gateway, permission, session, tracker, clock
class CallDetector(
    private val gateway: CallGateway,
    private val permissions: CallPermissions,
    private val session: TandemSession,
    private val tracker: CallTracker,
    private val normalize: (String) -> String?,
    private val clock: Clock,
    private val newCallId: () -> String = { UUID.randomUUID().toString() },
    private val onEnded: (durationSeconds: Long?) -> Unit = {},
    private val log: (String) -> Unit = {},
) {
    private var seeded = false
    private var unseenCallInProgress = false
    private var address = ""
    private var activeSinceMs: Long? = null

    suspend fun run() {
        if (!permissions.readPhoneState()) return
        gateway.callStates.collect { handle(it) }
    }

    private suspend fun handle(change: CallStateChange) {
        val first = !seeded
        seeded = true
        when (change.state) {
            PhoneCallState.Ringing -> {
                unseenCallInProgress = false
                start(CallDirection.CALL_DIRECTION_INCOMING, CallState.CALL_STATE_RINGING, change.number)
            }

            PhoneCallState.OffHook -> {
                offHook(first, change.number)
            }

            PhoneCallState.Idle -> {
                idle()
            }
        }
    }

    private suspend fun offHook(
        first: Boolean,
        number: String?,
    ) {
        val call = tracker.current
        when {
            call?.state == CallState.CALL_STATE_RINGING -> {
                activeSinceMs = clock.millis()
                move(call, CallState.CALL_STATE_ACTIVE)
            }

            call != null || unseenCallInProgress -> {
                Unit
            }

            first -> {
                unseenCallInProgress = true
            }

            else -> {
                start(CallDirection.CALL_DIRECTION_OUTGOING, CallState.CALL_STATE_DIALING, number)
            }
        }
    }

    private suspend fun idle() {
        unseenCallInProgress = false
        val call = tracker.current ?: return
        val activeSince = activeSinceMs
        send(call.callId, call.direction, CallState.CALL_STATE_ENDED)
        tracker.end()
        activeSinceMs = null
        onEnded(activeSince?.let { (clock.millis() - it) / MILLIS_PER_SECOND })
    }

    private suspend fun start(
        direction: CallDirection,
        state: CallState,
        number: String?,
    ) {
        address = number.orEmpty()
        val call = TrackedCall(newCallId(), direction, state)
        tracker.current = call
        send(call.callId, direction, state)
    }

    private suspend fun move(
        call: TrackedCall,
        state: CallState,
    ) {
        tracker.current = TrackedCall(call.callId, call.direction, state)
        send(call.callId, call.direction, state)
    }

    private suspend fun send(
        id: String,
        callDirection: CallDirection,
        callState: CallState,
    ) {
        log("call_event state=${callState.name} direction=${callDirection.name}")
        session.send(Channel.CHANNEL_CALLS) {
            callEvent =
                callEvent {
                    callId = id
                    direction = callDirection
                    state = callState
                    address = this@CallDetector.address
                    normalizedE164 =
                        this@CallDetector
                            .address
                            .takeIf(String::isNotEmpty)
                            ?.let(normalize)
                            .orEmpty()
                    timestampMs = clock.millis()
                }
        }
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1000L
    }
}
