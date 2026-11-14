package dev.tandem.app.ring

import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.sendOrDrop
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.RingStop
import dev.tandem.protocol.v1.ringStop
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/**
 * Owns the phone-side reaction to Ring/RingStop once [RingHandler] already knows how to start and
 * stop the alarm itself (E23-05): stops on phone-side user dismissal (the ring notification's
 * "Stop" action) and sends exactly one `RingStop{origin=phone}` on [session] so the Mac can revert
 * its menu item (E23-06, F-4.4, UC-06); stops on a `RingStop` received from the Mac without
 * echoing one back.
 *
 * Also enforces D-62: [ring] is a no-op while the alarm is already ringing, and starts it at most
 * twice per rolling 10 s window (cooldown) even across separate ring/stop cycles, so repeated
 * delivery of the same empty `Ring` message never double-starts or floods the alarm.
 *
 * Shows the ring notification (with its Stop action) while ringing and stops the alarm by itself
 * after [MAX_RING_DURATION], sending the same `RingStop{origin=phone}` as a user dismissal.
 *
 * Framework-free like [RingHandler]: reads [session] and [elapsedRealtimeSource] instead of a real
 * `TandemSession`/`SystemClock`, so it stays plain unit-tested against `FakeTandemSession`
 * (E12-11) and `FakeElapsedRealtime` (E00-18).
 */
class RingController(
    private val ringHandler: RingHandler,
    private val session: TandemSession,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
    private val ringNotifier: RingNotifier,
    private val scope: CoroutineScope,
) {
    private var isRinging = false
    private var timeoutJob: Job? = null
    private val recentStartTimestampsMillis = ArrayDeque<Long>()

    /** Reacts to a received `Ring` (D-62 idempotency and cooldown); returns true if the alarm started. */
    fun ring(): Boolean {
        val started = !isRinging && withinStartBudget()
        if (started) {
            recentStartTimestampsMillis.addLast(elapsedRealtimeSource.elapsedRealtimeMillis())
            isRinging = true
            LiveRingController.mutableRinging.value = true
            ringHandler.ring()
            ringNotifier.show()
            timeoutJob = scope.launch { stopAfterMaxDuration() }
        }
        return started
    }

    private suspend fun stopAfterMaxDuration() {
        delay(MAX_RING_DURATION)
        timeoutJob = null
        dismissedByPhone()
    }

    private fun withinStartBudget(): Boolean {
        val now = elapsedRealtimeSource.elapsedRealtimeMillis()
        while (recentStartTimestampsMillis.isNotEmpty() &&
            now - recentStartTimestampsMillis.first() >= COOLDOWN_WINDOW_MILLIS
        ) {
            recentStartTimestampsMillis.removeFirst()
        }
        return recentStartTimestampsMillis.size < MAX_STARTS_PER_WINDOW
    }

    /**
     * Phone-side user dismissal (e.g. the ring notification's "Stop" action): stops the alarm and
     * sends a single `RingStop{origin=phone}` so the Mac can revert its menu item (E23-07). A
     * no-op if the alarm isn't currently ringing, except that it clears a stale ring notification
     * (e.g. one left behind by a process death).
     */
    suspend fun dismissedByPhone() {
        if (!isRinging) {
            ringNotifier.cancel()
            return
        }
        stopRinging()
        session.sendOrDrop(Channel.CHANNEL_STATUS) { ringStop = ringStop { origin = RingStop.Origin.ORIGIN_PHONE } }
    }

    /**
     * A `RingStop` received from the Mac (any origin): stops the alarm; never echoes a `RingStop`
     * back. A no-op if the alarm isn't currently ringing.
     */
    fun ringStopReceived() {
        if (!isRinging) return
        stopRinging()
    }

    private fun stopRinging() {
        isRinging = false
        LiveRingController.mutableRinging.value = false
        timeoutJob?.cancel()
        timeoutJob = null
        ringHandler.stop()
        ringNotifier.cancel()
    }

    companion object {
        /** No ring duration is specified in PRD or SPEC; the alarm never outlives this. */
        val MAX_RING_DURATION = 2.minutes

        private const val MAX_STARTS_PER_WINDOW = 2
        private val COOLDOWN_WINDOW_MILLIS = 10.seconds.inWholeMilliseconds
    }
}
