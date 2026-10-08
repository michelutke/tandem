package dev.tandem.feature.calls

import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.CallActionErrorCode
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.PlaceCallRequest
import dev.tandem.protocol.v1.callActionResult
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.withContext

/**
 * E52-05 phone side of the Mac's `PlaceCallRequest` (PRD F-8.4, UC-21, docs/protocol/SPEC.md
 * #calls-channel "Place call"). Checks, in order: the address rule (`INVALID_NUMBER`, so MMI codes
 * like `**21*123#` never dial), CALL_PHONE (`PERMISSION_DENIED`), the SIM (`INVALID_SUBSCRIPTION`)
 * and the one-request-per-5-s limit (`RATE_LIMITED`); only then does it place the call through
 * [gateway]. When the OS will not start the call from the background it posts the "Tap to call"
 * notification through [notifier] and answers `NEEDS_PHONE_TAP`. [log] receives the path taken,
 * never the number (invariant 7).
 */
@Suppress("LongParameterList") // independent injected seams
class PlaceCallHandler(
    private val gateway: CallGateway,
    private val permissions: CallPermissions,
    private val subscriptions: CallSubscriptions,
    private val notifier: TapToCallNotifier,
    private val session: TandemSession,
    elapsed: ElapsedRealtimeSource,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: (String) -> Unit = {},
) {
    private val rateLimiter = PlaceCallRateLimiter(elapsed)

    suspend fun run() {
        session
            .receive(Channel.CHANNEL_CALLS)
            .filter { it.hasPlaceCallRequest() }
            .collect { handle(it.placeCallRequest) }
    }

    suspend fun handle(request: PlaceCallRequest) {
        val error = withContext(ioDispatcher) { place(request) }
        session.send(Channel.CHANNEL_CALLS) {
            callActionResult =
                callActionResult {
                    requestId = request.requestId
                    success = error == CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED
                    errorCode = error
                }
        }
    }

    private suspend fun place(request: PlaceCallRequest): CallActionErrorCode {
        val address = request.address.filterNot { it == ' ' || it == '-' }
        val rejection =
            when {
                !ADDRESS_RULE.matches(address) -> {
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_INVALID_NUMBER
                }

                !permissions.callPhone() -> {
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_PERMISSION_DENIED
                }

                request.subscriptionId != DEFAULT_SUBSCRIPTION && !subscriptions.isActive(request.subscriptionId) -> {
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_INVALID_SUBSCRIPTION
                }

                !rateLimiter.tryAcquire() -> {
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_RATE_LIMITED
                }

                else -> {
                    null
                }
            }
        if (rejection != null) {
            log("place_call rejected=${rejection.name}")
            return rejection
        }
        return dial(address, request.subscriptionId)
    }

    private suspend fun dial(
        address: String,
        subscriptionId: Int,
    ): CallActionErrorCode =
        try {
            when (gateway.placeCall(address, subscriptionId)) {
                PlaceOutcome.Placed -> {
                    log("place_call path=direct")
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_UNSPECIFIED
                }

                PlaceOutcome.Blocked -> {
                    log("place_call path=tap_to_call_notification")
                    notifier.post(address, subscriptionId)
                    CallActionErrorCode.CALL_ACTION_ERROR_CODE_NEEDS_PHONE_TAP
                }
            }
        } catch (_: SecurityException) {
            CallActionErrorCode.CALL_ACTION_ERROR_CODE_PERMISSION_DENIED
        }

    private companion object {
        val ADDRESS_RULE = Regex("^\\+?[0-9]{3,20}$")
        const val DEFAULT_SUBSCRIPTION = 0
    }
}

/** At most one accepted request per [WINDOW_MS] (docs/protocol/SPEC.md #calls-channel "Place call"). */
class PlaceCallRateLimiter(
    private val elapsed: ElapsedRealtimeSource,
) {
    private var lastAcceptedMs: Long? = null

    @Synchronized
    fun tryAcquire(): Boolean {
        val now = elapsed.elapsedRealtimeMillis()
        val last = lastAcceptedMs
        if (last != null && now - last < WINDOW_MS) return false
        lastAcceptedMs = now
        return true
    }

    companion object {
        const val WINDOW_MS = 5_000L
    }
}
