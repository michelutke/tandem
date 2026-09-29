package dev.tandem.feature.notifications

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Duration
import java.time.Instant

/**
 * E30-12: rate-limits forwarding to at most one [forward] call per [window] per key, on the
 * sending side -- the Mac already replaces same-key updates (E30-07), so this only needs to bound
 * how often *this phone* forwards. A key updated inside its own window is coalesced: the newest
 * value replaces whatever was already pending for that key and is delivered once the window
 * elapses, so the final state is always delivered eventually. This mirrors `StatusPublisher`'s
 * throttle mechanism (E23-03) but keyed per notification instead of global.
 *
 * [clock]+[dispatcher] are the injected seams (E00-18): the coalesced send's delay is measured
 * against [clock] and runs on [dispatcher], so both advance together under
 * `TestClock`/`StandardTestDispatcher` in tests.
 *
 * [update]/[remove] are plain (non-suspend) calls, since [TandemNotificationListenerService]'s
 * callbacks that will drive this aren't suspend functions either; [lock] guards [states] since
 * those callbacks and the coalesced send itself (on [dispatcher]) are not guaranteed to run on the
 * same thread.
 */
class UpdateCoalescer<K : Any, V>(
    private val forward: (V) -> Unit,
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val window: Duration = DEFAULT_WINDOW,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val lock = Any()
    private val states = mutableMapOf<K, KeyState<V>>()

    private class KeyState<V> {
        var lastSendTime: Instant? = null
        var pendingJob: Job? = null
        var pendingValue: V? = null
    }

    /** Stops all pending coalesced sends and cancels this instance's scope. */
    fun close() {
        scope.cancel()
    }

    /**
     * Forwards [value] immediately if [key] hasn't been forwarded within [window]; otherwise
     * coalesces it with any value already pending for [key], to be forwarded once the window
     * elapses.
     */
    fun update(
        key: K,
        value: V,
    ) {
        val toSendNow: V?
        synchronized(lock) {
            val state = states.getOrPut(key) { KeyState() }
            val now = clock.instant()
            val last = state.lastSendTime
            toSendNow =
                if (last == null || Duration.between(last, now) >= window) {
                    cancelPendingLocked(state)
                    state.lastSendTime = now
                    value
                } else {
                    state.pendingValue = value
                    if (state.pendingJob == null) {
                        val delayMillis = Duration.between(now, last.plus(window)).toMillis()
                        state.pendingJob = scope.launch { fireAfter(key, delayMillis) }
                    }
                    null
                }
        }
        toSendNow?.let(forward)
    }

    /** Drops [key]'s state: a value already pending for it, if any, is never forwarded. */
    fun remove(key: K) {
        synchronized(lock) {
            states.remove(key)?.let { cancelPendingLocked(it) }
        }
    }

    private suspend fun fireAfter(
        key: K,
        delayMillis: Long,
    ) {
        delay(delayMillis)
        val toSend: V?
        synchronized(lock) {
            val state = states[key]
            toSend =
                if (state == null) {
                    null
                } else {
                    state.pendingJob = null
                    val value = state.pendingValue
                    state.pendingValue = null
                    if (value != null) state.lastSendTime = clock.instant()
                    value
                }
        }
        toSend?.let(forward)
    }

    private fun cancelPendingLocked(state: KeyState<V>) {
        state.pendingJob?.cancel()
        state.pendingJob = null
        state.pendingValue = null
    }

    private companion object {
        val DEFAULT_WINDOW: Duration = Duration.ofMillis(500)
    }
}
