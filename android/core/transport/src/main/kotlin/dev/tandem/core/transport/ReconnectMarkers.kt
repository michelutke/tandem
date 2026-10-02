package dev.tandem.core.transport

import android.util.Log

/**
 * E20-12 reconnect-harness markers: one `TandemReconnect event=<disconnected|dead|ready>` logcat line
 * per session transition, parsed by `tools/reconnect-harness`. Carries no peer, address or content.
 */
interface ReconnectMarkers {
    fun disconnected()

    fun dead()

    fun ready()

    object None : ReconnectMarkers {
        override fun disconnected() = Unit

        override fun dead() = Unit

        override fun ready() = Unit
    }
}

class LogcatReconnectMarkers : ReconnectMarkers {
    override fun disconnected() = emit("disconnected")

    override fun dead() = emit("dead")

    override fun ready() = emit("ready")

    private fun emit(event: String) {
        Log.i(TAG, "event=$event")
    }

    private companion object {
        const val TAG = "TandemReconnect"
    }
}
