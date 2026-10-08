package dev.tandem.feature.calls

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Production [CallGateway] (E52-02): state from `TelephonyCallback.CallStateListener`
 * (READ_PHONE_STATE), the number from [numbers] when [screeningRoleHeld], control through
 * `TelecomManager` (ANSWER_PHONE_CALLS, CALL_PHONE). `TelecomManager.placeCall` is not an activity
 * start, but a background placement can still be dropped by the OS without an error, so
 * [placeCall] confirms the platform actually left idle within [PLACE_CONFIRM_MS] and reports
 * [PlaceOutcome.Blocked] otherwise.
 */
@SuppressLint("MissingPermission") // CallActionHandler and PlaceCallHandler check the permissions first.
class TelecomCallGateway(
    private val telephonyManager: TelephonyManager,
    private val telecomManager: TelecomManager,
    private val numbers: IncomingNumberRelay,
    private val screeningRoleHeld: () -> Boolean,
) : CallGateway {
    constructor(context: Context, numbers: IncomingNumberRelay = IncomingNumberRelay.shared) : this(
        context.getSystemService(TelephonyManager::class.java),
        context.getSystemService(TelecomManager::class.java),
        numbers,
        { CallScreeningRole.isHeld(context) },
    )

    override val callStates: Flow<CallStateChange> =
        callbackFlow {
            val callback =
                object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        trySend(state)
                    }
                }
            telephonyManager.registerTelephonyCallback(Runnable::run, callback)
            awaitClose { telephonyManager.unregisterTelephonyCallback(callback) }
        }.map { toChange(it) }

    private suspend fun toChange(state: Int): CallStateChange =
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                CallStateChange(PhoneCallState.Ringing, screenedNumber())
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> {
                CallStateChange(PhoneCallState.OffHook, numbers.peek())
            }

            else -> {
                numbers.clear()
                CallStateChange(PhoneCallState.Idle)
            }
        }

    private suspend fun screenedNumber(): String? =
        if (screeningRoleHeld()) numbers.peek() ?: numbers.await(NUMBER_WAIT_MS) else null

    override fun acceptRingingCall() = telecomManager.acceptRingingCall()

    @Suppress("DEPRECATION") // deprecated from API 29, still the only way to end a call without an InCallService.
    override fun endCall(): Boolean = telecomManager.endCall()

    override suspend fun placeCall(
        address: String,
        subscriptionId: Int,
    ): PlaceOutcome {
        val extras = Bundle()
        callAccountFor(telephonyManager, telecomManager, subscriptionId)?.let {
            extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it)
        }
        numbers.publish(address)
        telecomManager.placeCall(Uri.fromParts("tel", address, null), extras)
        val started =
            withTimeoutOrNull(PLACE_CONFIRM_MS) { callStates.first { it.state != PhoneCallState.Idle } }
        if (started != null) return PlaceOutcome.Placed
        numbers.clear()
        return PlaceOutcome.Blocked
    }

    private companion object {
        const val NUMBER_WAIT_MS = 500L
        const val PLACE_CONFIRM_MS = 5_000L
    }
}

/** The call-capable account of SIM [subscriptionId], or null for the default SIM (0) or an unknown one. */
@SuppressLint("MissingPermission") // callers hold READ_PHONE_STATE (declared) or the lookup throws SecurityException.
internal fun callAccountFor(
    telephonyManager: TelephonyManager,
    telecomManager: TelecomManager,
    subscriptionId: Int,
): PhoneAccountHandle? =
    if (subscriptionId == 0) {
        null
    } else {
        telecomManager.callCapablePhoneAccounts.firstOrNull { telephonyManager.getSubscriptionId(it) == subscriptionId }
    }
