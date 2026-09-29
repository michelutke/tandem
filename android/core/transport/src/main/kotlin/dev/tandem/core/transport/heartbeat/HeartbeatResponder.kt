package dev.tandem.core.transport.heartbeat

import dev.tandem.core.protocol.multiplex.FrameArrival
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Phone-side reply half of the E01-07 liveness contract (E20-15; SPEC.md #heartbeat; the Mac half,
 * E20-05, never replies to a received `Heartbeat` -- the phone is the only side that ever does).
 * Every [received] `Heartbeat` on `CONTROL` gets exactly one reply via [sendHeartbeat], except
 * `docs/planning/decisions.md` D-60: replies less than [minReplyInterval] apart, measured on
 * [elapsedRealtimeSource] (sleep-inclusive, E00-18), are dropped silently -- no reply, no error, no
 * connection close.
 */
class HeartbeatResponder(
    private val received: Flow<FrameArrival>,
    private val sendHeartbeat: suspend () -> Unit,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    dispatcher: CoroutineDispatcher,
    private val minReplyInterval: Long = MIN_REPLY_INTERVAL_MILLIS,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null
    private var lastReplyAtMillis: Long? = null

    /** Starts collecting [received]. Idempotent: cancels and replaces any collection already running. */
    fun start() {
        job?.cancel()
        job =
            scope.launch {
                received.collect { arrival ->
                    if (arrival.channel == Channel.CHANNEL_CONTROL && arrival.isHeartbeat) {
                        onHeartbeatReceived()
                    }
                }
            }
    }

    private suspend fun onHeartbeatReceived() {
        val now = elapsedRealtimeSource.elapsedRealtimeMillis()
        val last = lastReplyAtMillis
        if (last != null && now - last < minReplyInterval) return // D-60: dropped silently
        lastReplyAtMillis = now
        sendHeartbeat()
    }

    /**
     * Stops collecting and cancels this instance's scope. Callers own this instance's lifetime
     * and MUST call this once done.
     */
    fun close() {
        scope.cancel()
    }

    private companion object {
        const val MIN_REPLY_INTERVAL_MILLIS = 1_000L
    }
}
