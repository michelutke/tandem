package dev.tandem.feature.calls

import dev.tandem.protocol.v1.CallDirection
import dev.tandem.protocol.v1.CallState

/** The call the phone currently knows. Not a data class: no `toString` leak of anything call-related. */
class TrackedCall(
    val callId: String,
    val direction: CallDirection,
    val state: CallState,
)

/** Shared view of the current call: [CallDetector] writes it, [CallActionHandler] reads it. */
class CallTracker {
    @Volatile
    var current: TrackedCall? = null
        internal set

    /** The most recently ended call, so a late action on it gets a precise error instead of UNKNOWN_CALL. */
    @Volatile
    var lastEndedCallId: String? = null
        private set

    internal fun end() {
        current?.let { lastEndedCallId = it.callId }
        current = null
    }
}
