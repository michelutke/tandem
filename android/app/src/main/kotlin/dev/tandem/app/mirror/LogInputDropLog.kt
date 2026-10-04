package dev.tandem.app.mirror

import android.util.Log
import dev.tandem.feature.input.DropLog
import dev.tandem.feature.input.GateDropReason

/** Reason and event type name only; never coordinates, text or any event content (invariant 7). */
class LogInputDropLog : DropLog {
    override fun dropped(
        reason: GateDropReason,
        eventType: String,
    ) {
        Log.w(TAG, "input_dropped reason=${reason.name} event=$eventType")
    }

    override fun rateLimited(count: Int) {
        Log.w(TAG, "input_rate_limited count=$count")
    }

    private companion object {
        const val TAG = "InputGate"
    }
}
