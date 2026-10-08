package dev.tandem.feature.notifications

import android.util.Log

/** Notification-mirroring state-transition log: event names and reason codes only (invariant 7). */
object NotifyLog {
    private const val TAG = "TandemNotify"

    @Suppress("SwallowedException") // android.util.Log is absent or unstubbed off-device (JVM tests, harness)
    fun event(
        name: String,
        reason: String? = null,
    ) {
        try {
            Log.i(TAG, if (reason == null) name else "$name reason=$reason")
        } catch (_: LinkageError) {
            return
        } catch (_: RuntimeException) {
            return
        }
    }
}
