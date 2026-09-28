package dev.tandem.app.ring

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.provider.Settings

/**
 * Seam over `AudioManager`/`MediaPlayer` (E23-05, F-4.4, UC-06): starting a ring sets
 * `STREAM_ALARM` to its max volume and starts a looping alarm-usage playback; stopping restores
 * the volume `STREAM_ALARM` had before the ring, so [RingHandler] stays plain unit-tested
 * (CLAUDE.md's Robolectric rule). [SystemAlarmPlayer] is the only production implementation.
 */
interface AlarmPlayer {
    fun start()

    fun stop()
}

/** Production implementation backed by the real `AudioManager` and `MediaPlayer`. */
class SystemAlarmPlayer(
    private val context: Context,
) : AlarmPlayer {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private var previousAlarmVolume = 0
    private var mediaPlayer: MediaPlayer? = null

    override fun start() {
        previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val maxAlarmVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarmVolume, 0)

        mediaPlayer =
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes
                        .Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(context, alarmSoundUri())
                isLooping = true
                prepare()
                start()
            }
    }

    /**
     * The device's default alarm sound, falling back to the system-settings alarm-alert URI when
     * no default is configured -- [RingtoneManager.getActualDefaultRingtoneUri] returns `null` on
     * a fresh device/managed-device image with no alarm sound set (confirmed via a real CI
     * instrumented-test crash: `MediaPlayer.setDataSource` throws `NullPointerException("uri
     * param can not be null")` when passed the unguarded null), not only in some theoretical edge
     * case.
     */
    private fun alarmSoundUri(): Uri =
        RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
            ?: Settings.System.DEFAULT_ALARM_ALERT_URI

    override fun stop() {
        mediaPlayer?.apply {
            stop()
            release()
        }
        mediaPlayer = null
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, previousAlarmVolume, 0)
    }
}
