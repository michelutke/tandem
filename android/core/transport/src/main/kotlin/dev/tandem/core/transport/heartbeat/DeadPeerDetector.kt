package dev.tandem.core.transport.heartbeat

import dev.tandem.core.transport.time.ElapsedRealtimeSource
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * Phone-side dead-peer half of the E01-07 liveness contract (E20-15; SPEC.md #heartbeat): silence
 * is measured on [elapsedRealtimeSource] (sleep-inclusive, E00-18) -- never wall clock, so it counts
 * real device sleep like any other silence and is immune to a wall-clock jump. Any [received] frame
 * resets the silence counter. Past [deadPeerThreshold] without one, [onDead] fires exactly once --
 * checked on this detector's own timer, and immediately on [deviceIdleSource] reporting Doze exit or
 * a screen-on event, so a long silence spent asleep is caught the moment the device wakes rather
 * than waiting for this detector's own coroutine `delay` to next get a chance to run.
 */
class DeadPeerDetector(
    private val received: Flow<Unit>,
    private val deviceIdleSource: DeviceIdleSource,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val onDead: () -> Unit,
    dispatcher: CoroutineDispatcher,
    private val deadPeerThreshold: Duration = DEFAULT_DEAD_PEER_THRESHOLD,
) {
    // Confined to a single thread (E20-15 verifier finding #4): `lastReceivedAtMillis`/`declaredDead`
    // are plain `var`s read and written from every one of this detector's observation loops, and a
    // production caller's `dispatcher` (e.g. `Dispatchers.IO`) is multi-threaded -- limiting this
    // scope to one thread makes every access to them effectively single-threaded without inventing a
    // separate locking scheme, matching `ChannelMultiplexer`'s own single-writer-loop discipline.
    private val scope = CoroutineScope(SupervisorJob() + dispatcher.limitedParallelism(1))
    private var timerJob: Job? = null
    private var lastReceivedAtMillis: Long = 0
    private var declaredDead = false

    /** Starts the timer and every observation loop. Idempotent. */
    fun start() {
        declaredDead = false
        lastReceivedAtMillis = elapsedRealtimeSource.elapsedRealtimeMillis()
        rescheduleTimer()
        scope.launch { received.collect { onFrameReceived() } }
        scope.launch {
            var wasIdle = deviceIdleSource.isIdle.value
            deviceIdleSource.isIdle.collect { idle ->
                if (wasIdle && !idle) evaluateNow() // Doze exit
                wasIdle = idle
            }
        }
        scope.launch { deviceIdleSource.screenOn.collect { evaluateNow() } }
    }

    private fun onFrameReceived() {
        lastReceivedAtMillis = elapsedRealtimeSource.elapsedRealtimeMillis()
        rescheduleTimer()
    }

    private fun rescheduleTimer() {
        if (declaredDead) return
        timerJob?.cancel()
        timerJob =
            scope.launch {
                // A small epsilon past the threshold itself: this timer's own fire time is the one
                // place silence is compared at exactly `deadPeerThreshold`, and SPEC.md's condition
                // is silence strictly greater than it.
                delay(deadPeerThreshold + TIMER_EPSILON)
                evaluateNow()
            }
    }

    private fun evaluateNow() {
        if (declaredDead) return
        val silence = elapsedRealtimeSource.elapsedRealtimeMillis() - lastReceivedAtMillis
        if (silence > deadPeerThreshold.inWholeMilliseconds) {
            declaredDead = true
            timerJob?.cancel()
            onDead()
        }
    }

    /**
     * Stops every timer/observation loop and cancels this instance's scope. Callers own this
     * instance's lifetime and MUST call this once done.
     */
    fun close() {
        scope.cancel()
    }

    private companion object {
        val DEFAULT_DEAD_PEER_THRESHOLD = 45.seconds
        val TIMER_EPSILON = 1.milliseconds
    }
}
