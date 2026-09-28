package dev.tandem.app.ring

/**
 * Handles the STATUS-channel Ring/RingStop flow on the phone side (E23-05, F-4.4, UC-06): [ring]
 * is called when `Ring` is received, [stop] when `RingStop` is received (or the phone dismisses
 * the alarm itself, E23-06). Always starts the looping alarm-usage playback at max `STREAM_ALARM`
 * volume, and additionally switches the interruption filter from total silence (`NONE`) to
 * `ALARMS` when Tandem holds notification policy access, restoring both on [stop].
 *
 * Framework-free: reads [alarmPlayer] and [notificationPolicyAccess] instead of
 * `AudioManager`/`MediaPlayer`/`NotificationManager` directly, so it stays plain unit-tested
 * against fakes (CLAUDE.md's Robolectric rule).
 */
class RingHandler(
    private val alarmPlayer: AlarmPlayer,
    private val notificationPolicyAccess: NotificationPolicyAccess,
) {
    /**
     * True once [ring] has run without notification policy access -- the caller shows
     * [RingPolicyExplanationScreen] before the user can open the policy access settings screen.
     */
    var needsPolicyExplanation: Boolean = false
        private set

    private var switchedFilterToAlarms = false

    fun ring() {
        needsPolicyExplanation = !notificationPolicyAccess.hasAccess()
        if (!needsPolicyExplanation && notificationPolicyAccess.currentFilter() == InterruptionFilter.NONE) {
            notificationPolicyAccess.setFilter(InterruptionFilter.ALARMS)
            switchedFilterToAlarms = true
        }
        alarmPlayer.start()
    }

    fun stop() {
        alarmPlayer.stop()
        if (switchedFilterToAlarms) {
            notificationPolicyAccess.setFilter(InterruptionFilter.NONE)
            switchedFilterToAlarms = false
        }
    }
}
