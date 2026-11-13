package dev.tandem.core.transport.heartbeat

import dev.tandem.core.protocol.multiplex.FrameArrival
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Phone-side receive cap on `CONTROL` frames (E20-15; SPEC.md §10 caps table, D-61, D-66): more than
 * [maxFrames] non-`Heartbeat` `CONTROL` frames within a sliding [windowMillis] window, measured on
 * [elapsedRealtimeSource], calls [onExceeded] once and stops counting. `Heartbeat`s are excluded on
 * the phone (Mac-sent ones are already bounded by the Mac's own 15 s interval, D-66); `CONTROL` is
 * exempt from credit flow control, so this is its only bound against an authenticated flood.
 */
class ControlFrameRateCap(
    private val received: Flow<FrameArrival>,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val onExceeded: () -> Unit,
    dispatcher: CoroutineDispatcher,
    private val maxFrames: Int = MAX_FRAMES,
    private val windowMillis: Long = WINDOW_MILLIS,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null
    private val arrivals = ArrayDeque<Long>()

    /** Starts collecting [received]. Idempotent: cancels and replaces any collection already running. */
    fun start() {
        job?.cancel()
        arrivals.clear()
        job =
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                received.collect { arrival ->
                    if (arrival.channel == Channel.CHANNEL_CONTROL && !arrival.isHeartbeat && countedOverCap()) {
                        onExceeded()
                        scope.cancel()
                    }
                }
            }
    }

    private fun countedOverCap(): Boolean {
        val now = elapsedRealtimeSource.elapsedRealtimeMillis()
        while (arrivals.isNotEmpty() && now - arrivals.first() >= windowMillis) arrivals.removeFirst()
        arrivals.addLast(now)
        return arrivals.size > maxFrames
    }

    /** Stops collecting and cancels this instance's scope. Callers own its lifetime and MUST call this once done. */
    fun close() {
        scope.cancel()
    }

    private companion object {
        const val MAX_FRAMES = 60
        const val WINDOW_MILLIS = 1_000L
    }
}
