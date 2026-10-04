package dev.tandem.feature.mirror

import dev.tandem.core.transport.ByteStream
import dev.tandem.protocol.v1.MediaCodec
import dev.tandem.protocol.v1.MediaMessage
import dev.tandem.protocol.v1.mediaFormat
import dev.tandem.protocol.v1.mediaMessage
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer

/**
 * Encodes the captured display and writes each encoder output buffer to the media connection as
 * `MediaFrame`s (E61-03; SPEC.md #media-frame-semantics). Frame content is never logged (invariant 7).
 * The caller must hold a granted MediaProjection consent (E61-02) before building [capture].
 */
class EncodePipeline(
    private val encoderFactory: EncoderFactory,
    private val capture: CaptureSource,
    private val config: EncoderConfig,
    private val stream: ByteStream,
    private val ioDispatcher: CoroutineDispatcher,
) {
    @Volatile
    private var encoder: VideoEncoder? = null

    private var bitrate = config.bitrateBitsPerSecond

    /** Runs until the encoder ends or the stream fails; always releases encoder and capture. */
    suspend fun run() =
        withContext(ioDispatcher) {
            val created = encoderFactory.create(config, capture)
            encoder = created
            try {
                writeMessage(mediaMessage { mediaFormat = config.toMediaFormat() })
                pump(created)
            } finally {
                encoder = null
                created.close()
                capture.stop()
            }
        }

    /** Mac -> phone `KeyframeRequest`. */
    fun onKeyframeRequest() {
        encoder?.requestSyncFrame()
    }

    private fun pump(encoder: VideoEncoder) {
        while (true) {
            val buffer = encoder.nextOutput() ?: return
            send(encoder, buffer)
        }
    }

    private fun send(
        encoder: VideoEncoder,
        buffer: EncodedBuffer,
    ) {
        val flags =
            (if (buffer.isKeyFrame) MediaFrameFragmenter.FLAG_KEYFRAME else 0) or
                (if (buffer.isCodecConfig) MediaFrameFragmenter.FLAG_CODEC_CONFIG else 0)
        val fragments = MediaFrameFragmenter.fragment(buffer.data, buffer.ptsMicros.coerceAtLeast(0), flags)
        if (fragments == null) {
            bitrate /= 2
            encoder.setBitrate(bitrate)
            encoder.requestSyncFrame()
            return
        }
        fragments.forEach { writeMessage(mediaMessage { mediaFrame = it }) }
    }

    private fun writeMessage(message: MediaMessage) {
        val body = message.toByteArray()
        stream.output.write(
            ByteBuffer
                .allocate(LENGTH_PREFIX_BYTES + body.size)
                .putInt(body.size)
                .put(body)
                .array(),
        )
        stream.output.flush()
    }

    private fun EncoderConfig.toMediaFormat() =
        mediaFormat {
            codec = if (mimeType == MIME_HEVC) MediaCodec.MEDIA_CODEC_HEVC else MediaCodec.MEDIA_CODEC_H264
            width = this@toMediaFormat.width
            height = this@toMediaFormat.height
            fps = frameRate
        }

    private companion object {
        const val LENGTH_PREFIX_BYTES = 4
        const val MIME_HEVC = "video/hevc"
    }
}
