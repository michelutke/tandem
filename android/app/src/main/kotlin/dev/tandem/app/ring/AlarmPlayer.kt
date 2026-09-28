package dev.tandem.app.ring

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
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
    private var toneGenerator: ToneGenerator? = null

    override fun start() {
        previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val maxAlarmVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarmVolume, 0)

        // A device can legitimately have zero installed alarm sounds -- confirmed by real CI
        // failures, not a theoretical edge case: one managed-device image had
        // `RingtoneManager.getActualDefaultRingtoneUri` return null AND the
        // `Settings.System.DEFAULT_ALARM_ALERT_URI` fallback itself fail `setDataSource` with
        // `IOException: setDataSource failed.: status=0x80000000`. `ToneGenerator` needs no audio
        // asset at all and is the final fallback, so the phone always actually rings (max volume +
        // an audible tone), never just maxes the volume on silence.
        val started = startMediaPlayer()
        mediaPlayer = started
        if (started == null) startToneGenerator()
    }

    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    // MediaPlayer.setDataSource/prepare document IOException, IllegalStateException,
    // IllegalArgumentException and SecurityException as all possible on a real device (confirmed:
    // a real CI failure threw IOException); any of them means "fall back to ToneGenerator", so a
    // single broad catch is the correct shape here, not a narrowing to guess at up front.
    private fun startMediaPlayer(): MediaPlayer? {
        val player = MediaPlayer()
        return try {
            player.apply {
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
        } catch (error: Exception) {
            player.release()
            null
        }
    }

    /** Loops [ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD] on `STREAM_ALARM` until [stop]. */
    private fun startToneGenerator() {
        toneGenerator =
            ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME).apply {
                startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD)
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
        toneGenerator?.apply {
            stopTone()
            release()
        }
        toneGenerator = null
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, previousAlarmVolume, 0)
    }
}
