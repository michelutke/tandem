package dev.tandem.app.ring

import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.RingStop
import dev.tandem.protocol.v1.ringStop
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
 * Framework-free like [RingHandler]: reads [session] and [elapsedRealtimeSource] instead of a real
 * `TandemSession`/`SystemClock`, so it stays plain unit-tested against `FakeTandemSession`
 * (E12-11) and `FakeElapsedRealtime` (E00-18).
 */
class RingController(
    private val ringHandler: RingHandler,
    private val session: TandemSession,
    private val elapsedRealtimeSource: ElapsedRealtimeSource,
) {
    private var isRinging = false
    private val recentStartTimestampsMillis = ArrayDeque<Long>()

    /** Reacts to a received `Ring`: starts the alarm, subject to D-62's idempotency and cooldown. */
    fun ring() {
        if (isRinging) return

        val now = elapsedRealtimeSource.elapsedRealtimeMillis()
        while (recentStartTimestampsMillis.isNotEmpty() &&
            now - recentStartTimestampsMillis.first() >= COOLDOWN_WINDOW_MILLIS
        ) {
            recentStartTimestampsMillis.removeFirst()
        }
        if (recentStartTimestampsMillis.size >= MAX_STARTS_PER_WINDOW) return

        recentStartTimestampsMillis.addLast(now)
        isRinging = true
        ringHandler.ring()
    }

    /**
     * Phone-side user dismissal (e.g. the ring notification's "Stop" action): stops the alarm and
     * sends a single `RingStop{origin=phone}` so the Mac can revert its menu item (E23-07). A
     * no-op if the alarm isn't currently ringing.
     */
    suspend fun dismissedByPhone() {
        if (!isRinging) return
        isRinging = false
        ringHandler.stop()
        session.send(Channel.CHANNEL_STATUS) { ringStop = ringStop { origin = RingStop.Origin.ORIGIN_PHONE } }
    }

    /**
     * A `RingStop` received from the Mac (any origin): stops the alarm; never echoes a `RingStop`
     * back. A no-op if the alarm isn't currently ringing.
     */
    fun ringStopReceived() {
        if (!isRinging) return
        isRinging = false
        ringHandler.stop()
    }

    private companion object {
        const val MAX_STARTS_PER_WINDOW = 2
        val COOLDOWN_WINDOW_MILLIS = 10.seconds.inWholeMilliseconds
    }
}
