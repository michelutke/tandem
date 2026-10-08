package dev.tandem.feature.calls

import kotlinx.coroutines.flow.Flow

/** The platform call states [CallGateway.callStates] reports (`TelephonyManager.CALL_STATE_*`). */
enum class PhoneCallState {
    Ringing,
    OffHook,
    Idle,
}

/**
 * One platform call-state change. [number] is the caller (or dialled) number when the call-screening
 * role supplied one, else null. Deliberately not a data class: no `toString` leak of the number.
 */
class CallStateChange(
    val state: PhoneCallState,
    val number: String? = null,
)

enum class PlaceOutcome {
    Placed,

    /** The OS did not start the call from the background; the user must tap to place it. */
    Blocked,
}

/**
 * E52-03 feature-local seam over the platform call APIs. Production is [TelecomCallGateway];
 * tests use `FakeCallGateway`. Collecting [callStates] registers the platform callback; the first
 * emission is the current state.
 */
interface CallGateway {
    val callStates: Flow<CallStateChange>

    fun acceptRingingCall()

    /** Ends the ringing, dialling or active call; false when the platform ended nothing. */
    fun endCall(): Boolean

    suspend fun placeCall(
        address: String,
        subscriptionId: Int,
    ): PlaceOutcome
}

/** Seam over the runtime permissions the call features need, read at use time. */
interface CallPermissions {
    fun readPhoneState(): Boolean

    fun answerPhoneCalls(): Boolean

    fun callPhone(): Boolean
}

/** Seam over `SubscriptionManager` for validating a [dev.tandem.protocol.v1.PlaceCallRequest]'s SIM. */
fun interface CallSubscriptions {
    fun isActive(subscriptionId: Int): Boolean
}

/** Posts the "Tap to call" fallback notification (E52-05) when the OS will not start a call from the background. */
fun interface TapToCallNotifier {
    fun post(
        address: String,
        subscriptionId: Int,
    )
}
