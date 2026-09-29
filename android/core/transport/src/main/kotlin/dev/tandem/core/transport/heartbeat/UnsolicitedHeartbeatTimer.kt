package dev.tandem.core.transport.heartbeat

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Phone-side unsolicited-send half of the E01-07 liveness contract (E20-15; SPEC.md #heartbeat):
 * while interactive and not in Doze, sends one `Heartbeat` after [idleSendInterval] without this
 * connection sending anything -- any frame on [sent] resets the timer, not only a `Heartbeat`
 * itself, mirroring the macOS twin's own idle-send timer (E20-05). While [isIdle] reports `true`,
 * this schedules nothing at all -- no wake lock, no `AlarmManager` alarm, not even this class's own
 * coroutine `delay` -- so an incoming Mac heartbeat is what wakes the phone instead (SPEC.md
 * #heartbeat).
 */
class UnsolicitedHeartbeatTimer(
    private val sent: Flow<Unit>,
    private val isIdle: StateFlow<Boolean>,
    private val sendHeartbeat: suspend () -> Unit,
    dispatcher: CoroutineDispatcher,
    private val idleSendInterval: Duration = DEFAULT_IDLE_SEND_INTERVAL,
) {
    // Confined to a single thread (E20-15 verifier finding #4): `timerJob` is a plain `var` read and
    // written from `sent`'s/`isIdle`'s own collect loops plus `start()`/`close()`, and a production
    // caller's `dispatcher` (e.g. `Dispatchers.IO`) is multi-threaded -- limiting this scope to one
    // thread makes every access effectively single-threaded, matching `ChannelMultiplexer`'s own
    // single-writer-loop discipline.
    private val scope = CoroutineScope(SupervisorJob() + dispatcher.limitedParallelism(1))
    private var timerJob: Job? = null

    /** Starts the timer and both observation loops. Idempotent. */
    fun start() {
        rescheduleOrCancel()
        scope.launch { sent.collect { rescheduleOrCancel() } }
        scope.launch { isIdle.collect { rescheduleOrCancel() } }
    }

    private fun rescheduleOrCancel() {
        timerJob?.cancel()
        timerJob = null
        if (isIdle.value) return
        timerJob =
            scope.launch {
                delay(idleSendInterval)
                sendHeartbeat()
            }
    }

    /**
     * Stops the timer and cancels this instance's scope. Callers own this instance's lifetime and
     * MUST call this once done.
     */
    fun close() {
        scope.cancel()
    }

    private companion object {
        val DEFAULT_IDLE_SEND_INTERVAL = 15.seconds
    }
}
