package dev.tandem.app.ring

/**
 * Recording fake for [AlarmPlayer] (E23-05): models the alarm stream volume as plain state instead
 * of touching `AudioManager`/`MediaPlayer`, so [RingHandler] stays plain unit-tested (CLAUDE.md's
 * Robolectric rule).
 */
class FakeAlarmPlayer(
    initialVolume: Int = INITIAL_VOLUME,
    private val maxVolume: Int = MAX_VOLUME,
) : AlarmPlayer {
    var alarmVolume: Int = initialVolume
        private set
    var isPlaying: Boolean = false
        private set

    private var volumeBeforeStart = initialVolume

    override fun start() {
        volumeBeforeStart = alarmVolume
        alarmVolume = maxVolume
        isPlaying = true
    }

    override fun stop() {
        isPlaying = false
        alarmVolume = volumeBeforeStart
    }

    companion object {
        const val INITIAL_VOLUME = 5
        const val MAX_VOLUME = 15
    }
}
