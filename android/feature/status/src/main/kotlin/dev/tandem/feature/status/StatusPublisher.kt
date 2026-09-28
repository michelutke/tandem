package dev.tandem.feature.status

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Clock
import java.time.Duration
import java.time.Instant

/**
 * Publishes [status] onto the STATUS channel via [session] (E23-03; SPEC.md E23-01's throttle
 * rule, PRD F-4.3): a change is sent immediately if no [DeviceStatus] was sent in the last
 * [throttleWindow]; otherwise changes are coalesced and only the latest value is sent, at
 * last-send-time + [throttleWindow] -- no periodic send ever happens absent an actual change. The
 * moment [session] becomes [ConnectionState.Ready] the current status is sent immediately,
 * bypassing the throttle window entirely (a fresh connection has no status yet) and cancelling
 * any already-scheduled coalesced send so it isn't sent again at its original deadline.
 *
 * Coalescing mechanism: a change inside the throttle window doesn't reschedule a new timer each
 * time -- it replaces [pendingValue] and leaves the single [pendingJob] (a `delay` until
 * last-send-time + [throttleWindow]) already counting down alone; that job sends whatever
 * [pendingValue] holds when it fires.
 *
 * [clock]+[dispatcher] are the injected seams (E00-18): the coalesced send's delay is measured
 * against [clock] and runs on [dispatcher], so both advance together under
 * `TestClock`/`StandardTestDispatcher` in tests.
 *
 * [lock] guards every field below: [status]'s collector and [session]'s state collector are two
 * separately launched coroutines, not guaranteed to run on the same thread even when [dispatcher]
 * happens to be single-threaded (mirrors `NotificationSink`, E30-16); [session.send] itself is
 * always called outside [lock], again mirroring `NotificationSink`, since it suspends on channel
 * credit.
 */
class StatusPublisher(
    private val status: Flow<DeviceStatus>,
    private val session: TandemSession,
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val throttleWindow: Duration = DEFAULT_THROTTLE_WINDOW,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val lock = Mutex()

    private var lastSendTime: Instant? = null
    private var pendingJob: Job? = null
    private var pendingValue: DeviceStatus? = null
    private var latestValue: DeviceStatus? = null

    init {
        scope.launch { status.collect { value -> onStatusChanged(value) } }
        scope.launch { session.state.collect { state -> onStateChanged(state) } }
    }

    /**
     * Stops publishing and cancels this instance's scope. Callers own this instance's lifetime
     * and MUST call this once done with it.
     */
    fun close() {
        scope.cancel()
    }

    private suspend fun onStatusChanged(value: DeviceStatus) {
        val toSendNow =
            lock.withLock {
                latestValue = value
                val now = clock.instant()
                val last = lastSendTime
                if (last == null || Duration.between(last, now) >= throttleWindow) {
                    cancelPendingLocked()
                    lastSendTime = now
                    value
                } else {
                    pendingValue = value
                    if (pendingJob == null) {
                        val delayMillis = Duration.between(now, last.plus(throttleWindow)).toMillis()
                        pendingJob = scope.launch { fireAfter(delayMillis) }
                    }
                    null
                }
            }
        toSendNow?.let { send(it) }
    }

    private suspend fun fireAfter(delayMillis: Long) {
        delay(delayMillis)
        val toSend =
            lock.withLock {
                pendingJob = null
                val value = pendingValue
                pendingValue = null
                if (value != null) lastSendTime = clock.instant()
                value
            }
        toSend?.let { send(it) }
    }

    private suspend fun onStateChanged(state: ConnectionState) {
        if (state !is ConnectionState.Ready) return
        val toSend =
            lock.withLock {
                val current = latestValue
                if (current != null) {
                    cancelPendingLocked()
                    lastSendTime = clock.instant()
                }
                current
            }
        toSend?.let { send(it) }
    }

    /** Caller must hold [lock]. */
    private fun cancelPendingLocked() {
        pendingJob?.cancel()
        pendingJob = null
        pendingValue = null
    }

    private suspend fun send(value: DeviceStatus) {
        session.send(Channel.CHANNEL_STATUS) { deviceStatus = value }
    }

    private companion object {
        val DEFAULT_THROTTLE_WINDOW: Duration = Duration.ofSeconds(60)
    }
}
