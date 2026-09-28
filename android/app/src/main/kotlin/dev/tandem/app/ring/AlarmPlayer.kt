package dev.tandem.app.ring

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.provider.Settings
import kotlin.math.sin

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
    private var synthesizedTone: AudioTrack? = null

    override fun start() {
        previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        val maxAlarmVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarmVolume, 0)

        // A device can legitimately have zero installed alarm sounds -- confirmed by real CI
        // failures, not a theoretical edge case: one managed-device image had
        // `RingtoneManager.getActualDefaultRingtoneUri` return null AND the
        // `Settings.System.DEFAULT_ALARM_ALERT_URI` fallback itself fail `setDataSource` with
        // `IOException: setDataSource failed.: status=0x80000000`. The fallback must still be an
        // `AudioTrack`-backed player (same as `MediaPlayer` uses internally) rather than
        // `ToneGenerator` -- confirmed by direct experiment on a real device that `ToneGenerator`
        // playback never appears in `AudioManager.activePlaybackConfigurations()` at all (it's
        // documented as a hardware-backed player type invisible to that tracking API), so a
        // `ToneGenerator` fallback would make the phone ring but leave `RingStopActionReceiver`'s
        // own real acceptance criterion structurally unverifiable, not just on CI.
        val started = startMediaPlayer()
        mediaPlayer = started
        if (started == null) synthesizedTone = startSynthesizedTone()
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

    /**
     * A 441 Hz sine wave, looped via `AudioTrack`'s own static-buffer loop points (no periodic
     * re-writing needed) until [stop]. Deliberately `AudioTrack`, not `ToneGenerator`: confirmed by
     * direct experiment on a real device that `ToneGenerator` playback never appears in
     * `AudioManager.activePlaybackConfigurations()` -- `MediaPlayer` itself plays back through an
     * internal `AudioTrack`, which is why that same query reliably sees it, so this fallback uses
     * the same underlying mechanism to stay consistent with what the app (and its own instrumented
     * tests) can actually observe.
     */
    private fun startSynthesizedTone(): AudioTrack {
        val frameCount = SYNTHESIZED_TONE_PERIOD_SAMPLES * SYNTHESIZED_TONE_PERIODS
        val buffer =
            ShortArray(frameCount) { frame ->
                val phase = 2.0 * Math.PI * frame / SYNTHESIZED_TONE_PERIOD_SAMPLES
                (sin(phase) * Short.MAX_VALUE).toInt().toShort()
            }
        val track =
            AudioTrack
                .Builder()
                .setAudioAttributes(
                    AudioAttributes
                        .Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                ).setAudioFormat(
                    AudioFormat
                        .Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SYNTHESIZED_TONE_SAMPLE_RATE_HZ)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                ).setBufferSizeInBytes(frameCount * Short.SIZE_BYTES)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
        track.write(buffer, 0, frameCount)
        track.setLoopPoints(0, frameCount, -1)
        track.play()
        return track
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
        synthesizedTone?.apply {
            stop()
            release()
        }
        synthesizedTone = null
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, previousAlarmVolume, 0)
    }

    private companion object {
        const val SYNTHESIZED_TONE_SAMPLE_RATE_HZ = 44_100
        const val SYNTHESIZED_TONE_PERIOD_SAMPLES = 100 // 441 Hz (44_100 / 100), an audible alert tone.
        const val SYNTHESIZED_TONE_PERIODS = 10 // ~23ms buffer, looped -- an exact whole number of cycles.
    }
}
