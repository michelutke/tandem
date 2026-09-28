package dev.tandem.core.transport.reconnect

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Duration
import java.time.Instant

/**
 * Bridges [NetworkMonitor] into [ReconnectStrategy] (E20-07): a network-available event kicks
 * the strategy so a pending backoff wait doesn't have to elapse before the next attempt. Applies
 * a leading-edge 500 ms debounce window -- the first event in a burst kicks immediately (0 s
 * virtual time), and further events within [debounceWindow] of the last kick are absorbed rather
 * than each triggering their own attempt (acceptance: "five events within 500 ms, one immediate
 * attempt").
 *
 * [ReconnectStrategy.kick] is itself a no-op unless the strategy's loop is currently running and
 * waiting on its backoff delay (e.g. already connected, or not yet started for the current
 * disconnect) -- this trigger doesn't need its own "are we already connected" check, since there
 * is nothing listening to react to a stale kick in that case (acceptance: "no attempt is
 * triggered while the connection is already Connected").
 *
 * [clock]+[dispatcher] are the injected time seams (E00-18): the debounce window is measured
 * against [clock], and the collecting coroutine runs on [dispatcher], so both advance together
 * under `TestClock`/`StandardTestDispatcher` in tests.
 */
class NetworkReconnectTrigger(
    private val networkMonitor: NetworkMonitor,
    private val reconnectStrategy: ReconnectStrategy,
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val debounceWindow: Duration = DEFAULT_DEBOUNCE_WINDOW,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var job: Job? = null
    private var lastKickAt: Instant? = null

    /** Starts collecting [NetworkMonitor.available]. Idempotent: replaces any existing collector. */
    fun start() {
        job?.cancel()
        lastKickAt = null
        job =
            scope.launch {
                networkMonitor.available.collect {
                    val now = clock.instant()
                    val last = lastKickAt
                    if (last == null || Duration.between(last, now) >= debounceWindow) {
                        lastKickAt = now
                        reconnectStrategy.kick()
                    }
                }
            }
    }

    /** Stops collecting. Callers own this instance's lifetime and MUST call [close] once done. */
    fun stop() {
        job?.cancel()
        job = null
    }

    /** Stops collecting and cancels this instance's scope. */
    fun close() {
        scope.cancel()
    }

    private companion object {
        val DEFAULT_DEBOUNCE_WINDOW: Duration = Duration.ofMillis(500)
    }
}
