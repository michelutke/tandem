package dev.tandem.feature.mirror

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Bundle

/** Real [EncoderFactory]: a surface-input `MediaCodec` configured from [EncoderConfig]. */
class MediaCodecEncoderFactory : EncoderFactory {
    override fun create(
        config: EncoderConfig,
        capture: CaptureSource,
    ): VideoEncoder {
        val codec = MediaCodec.createEncoderByType(config.mimeType)
        codec.configure(config.toMediaFormat(), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = codec.createInputSurface()
        codec.start()
        capture.start(surface)
        return MediaCodecVideoEncoder(codec)
    }

    private fun EncoderConfig.toMediaFormat(): MediaFormat =
        MediaFormat.createVideoFormat(mimeType, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateBitsPerSecond)
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, iFrameIntervalSeconds)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileConstrainedBaseline)
            setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel41)
            setInteger(MediaFormat.KEY_PRIORITY, priority)
            lowLatency?.let { setInteger(KEY_LOW_LATENCY, it) }
        }

    private companion object {
        const val KEY_LOW_LATENCY = "low-latency"
    }
}

private class MediaCodecVideoEncoder(
    private val codec: MediaCodec,
) : VideoEncoder {
    @Volatile
    private var closed = false

    override fun requestSyncFrame() {
        codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
    }

    override fun setBitrate(bitsPerSecond: Int) {
        codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitsPerSecond) })
    }

    override fun nextOutput(): EncodedBuffer? =
        try {
            dequeueNext()
        } catch (_: IllegalStateException) {
            null
        }

    private fun dequeueNext(): EncodedBuffer? {
        val info = MediaCodec.BufferInfo()
        var index = MediaCodec.INFO_TRY_AGAIN_LATER
        while (!closed && index < 0) index = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_MICROS)
        if (closed) return null
        val data = ByteArray(info.size)
        codec.getOutputBuffer(index)?.apply {
            position(info.offset)
            get(data)
        }
        codec.releaseOutputBuffer(index, false)
        return EncodedBuffer(
            data = data,
            ptsMicros = info.presentationTimeUs,
            isKeyFrame = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0,
            isCodecConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0,
        ).takeUnless { info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0 }
    }

    override fun close() {
        closed = true
        codec.stop()
        codec.release()
    }

    private companion object {
        const val DEQUEUE_TIMEOUT_MICROS = 100_000L
    }
}
