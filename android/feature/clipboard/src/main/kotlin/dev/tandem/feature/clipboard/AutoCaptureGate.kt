package dev.tandem.feature.clipboard

import dev.tandem.core.transport.time.ElapsedRealtimeSource

/** Whether the opt-in "send copies to Mac automatically" setting is on (ADR-007). Off by default. */
object LiveClipboardAutoCapture {
    @Volatile
    var isEnabled: () -> Boolean = { false }
}

/**
 * Decides whether a detected copy should start a capture: the setting is on, a Mac session is live,
 * and the previous capture was at least [debounceMillis] ago. Calling [tryAcquire] records the
 * attempt, so a burst of overlay events yields one capture.
 */
class AutoCaptureGate(
    private val isEnabled: () -> Boolean,
    private val hasSession: () -> Boolean,
    private val clock: ElapsedRealtimeSource,
    private val debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
) {
    private var lastAcquiredAt: Long? = null

    @Synchronized
    fun tryAcquire(): Boolean {
        if (!isEnabled() || !hasSession()) return false
        val now = clock.elapsedRealtimeMillis()
        val last = lastAcquiredAt
        val debounced = last != null && now - last < debounceMillis
        if (!debounced) lastAcquiredAt = now
        return !debounced
    }

    companion object {
        const val DEFAULT_DEBOUNCE_MILLIS = 1_500L
    }
}
