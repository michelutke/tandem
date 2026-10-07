package dev.tandem.feature.files

import android.util.Log
import dev.tandem.protocol.v1.TransferReason

/** FILES state-transition log: event names and reason codes only, never names, contents or URIs (invariant 7). */
internal object FilesLog {
    private const val TAG = "TandemFiles"

    @Suppress("TooGenericExceptionCaught", "SwallowedException") // android.util.Log is unstubbed in plain JVM tests
    fun event(
        name: String,
        reason: TransferReason? = null,
    ) {
        try {
            Log.i(TAG, if (reason == null) name else "$name reason=${reason.name}")
        } catch (_: RuntimeException) {
            return
        }
    }
}
