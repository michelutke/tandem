package dev.tandem.feature.calls

import android.telecom.Call
import android.telecom.CallScreeningService

/**
 * Exists only to read the caller number (E52-02, owner decision 2026-10-08): the call-screening
 * role is the one permission-light source of it on API 31+. It never blocks, silences, rejects or
 * alters a call; every call, incoming or outgoing, gets the default allow response. The number
 * goes to [IncomingNumberRelay] and nowhere else (invariant 7).
 */
class TandemCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        IncomingNumberRelay.shared.publish(callDetails.handle?.schemeSpecificPart)
        respondToCall(callDetails, CallResponse.Builder().build())
    }
}
