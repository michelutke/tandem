package dev.tandem.harness.jvmclient

import java.time.Clock
import java.time.Duration

/**
 * Harness-local reactor for the phone-side Ring/RingStop reaction (E23-08): mirrors
 * `dev.tandem.app.ring.RingController`/`RingHandler`'s documented behavior (D-62 idempotency and
 * the 2-starts-per-rolling-10s cooldown) instead of reusing those classes directly. `:app` is a
 * `com.android.application` module whose runtime graph pulls in the full androidx.compose BOM
 * (`RingPolicyExplanationScreen.kt`, a sibling file in the same package) -- AAR-only artifacts
 * with no plain-jar variant a bare JVM classpath can resolve. Confirmed by actually attempting
 * `implementation(project(":app"))` in this module's `build.gradle.kts`: resolution fails on
 * `androidx.compose.ui:ui-test-manifest` and its siblings even after excluding `hilt-android` and
 * `androidx.core` the same way that file already does for `:feature:status` -- see that file's
 * comment for the full trail. Reusing `RingController` for real would need a larger module split
 * (moving it and `RingHandler` out of `:app`) than this test-only issue's scope.
 *
 * Stands in for the real `AlarmPlayer`/hardware alarm the same way `FakeAlarmPlayer`
 * (`android/app/src/test/kotlin/dev/tandem/app/ring/FakeAlarmPlayer.kt`) does for
 * `RingHandlerTest` -- a start/stop counter, not real audio; [HarnessCli] wires this reactor to
 * every `Ring`/`RingStop` this process's session actually receives on the wire, so the counting
 * and cooldown decisions below run against real, network-delivered frames, not a scripted list.
 */
class HarnessRingReactor(
    private val clock: Clock = Clock.systemUTC(),
) {
    private var isRinging = false
    private val recentStartTimestampsMillis = ArrayDeque<Long>()

    /** Number of times [ring] actually started the alarm (subject to the cooldown below). */
    var startCount: Int = 0
        private set

    /** Number of times [ringStopReceived] actually stopped the alarm. */
    var stopCount: Int = 0
        private set

    /** True while the alarm is (believed) currently ringing. */
    val isCurrentlyRinging: Boolean
        @Synchronized get() = isRinging

    /**
     * A received `Ring`: starts the alarm and returns `true`, unless already ringing (D-62
     * idempotency) or this would be more than [MAX_STARTS_PER_WINDOW] starts within the trailing
     * [COOLDOWN_WINDOW_MILLIS], in which case it is a no-op and returns `false`.
     */
    @Synchronized
    fun ring(): Boolean {
        if (isRinging) return false
        val now = clock.instant().toEpochMilli()
        while (recentStartTimestampsMillis.isNotEmpty() &&
            now - recentStartTimestampsMillis.first() >= COOLDOWN_WINDOW_MILLIS
        ) {
            recentStartTimestampsMillis.removeFirst()
        }
        if (recentStartTimestampsMillis.size >= MAX_STARTS_PER_WINDOW) return false
        recentStartTimestampsMillis.addLast(now)
        isRinging = true
        startCount++
        return true
    }

    /** A received `RingStop` (any origin): stops the alarm and returns `true`, or `false` if it wasn't ringing. */
    @Synchronized
    fun ringStopReceived(): Boolean {
        if (!isRinging) return false
        isRinging = false
        stopCount++
        return true
    }

    private companion object {
        const val MAX_STARTS_PER_WINDOW = 2
        val COOLDOWN_WINDOW_MILLIS: Long = Duration.ofSeconds(10).toMillis()
    }
}
