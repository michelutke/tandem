package dev.tandem.feature.mirror

import dev.tandem.core.transport.ByteStream
import dev.tandem.protocol.v1.MediaCodec
import dev.tandem.protocol.v1.MediaMessage
import dev.tandem.protocol.v1.mediaFormat
import dev.tandem.protocol.v1.mediaMessage
import dev.tandem.protocol.v1.rotationChanged
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Encodes the captured display and writes each encoder output buffer to the media connection as
 * `MediaFrame`s (E61-03; SPEC.md #media-frame-semantics). Frame content is never logged (invariant 7).
 * The caller must hold a granted MediaProjection consent (E61-02) before building [capture].
 * Encoder, capture (VirtualDisplay + MediaProjection) and [stream] are released exactly once,
 * whether the run ends on its own, on a stream failure, on [stop] or on a system capture stop.
 */
class EncodePipeline(
    private val encoderFactory: EncoderFactory,
    private val capture: CaptureSource,
    config: EncoderConfig,
    private val stream: ByteStream,
    private val ioDispatcher: CoroutineDispatcher,
    private val displayChanges: DisplayChangeSource = NoDisplayChanges,
) {
    private var config = config

    private val lock = Any()

    @Volatile
    private var encoder: VideoEncoder? = null

    private var bitrate = config.bitrateBitsPerSecond

    private val released = AtomicBoolean(false)

    /** Runs until the encoder ends or the stream fails; always releases encoder, capture and stream. */
    suspend fun run() =
        withContext(ioDispatcher) {
            if (released.get()) return@withContext
            capture.setStopListener(::stop)
            val created = encoderFactory.create(config, capture)
            encoder = created
            if (released.get()) {
                created.close()
                capture.stop()
                return@withContext
            }
            try {
                synchronized(lock) { writeMessage(mediaMessage { mediaFormat = config.toMediaFormat() }) }
                displayChanges.start(::onDisplayChanged)
                pump()
            } finally {
                release()
            }
        }

    /** Idempotent: ends [run] and releases encoder, capture and the media stream. */
    fun stop() = release()

    /** Mac -> phone `KeyframeRequest`. */
    fun onKeyframeRequest() {
        encoder?.requestSyncFrame()
    }

    /**
     * Recreates the encoder and VirtualDisplay at the planned size, then sends `RotationChanged` and the new
     * `MediaFormat` before any frame of the new geometry; the new encoder is asked for a keyframe.
     */
    private fun onDisplayChanged(geometry: DisplayGeometry) {
        synchronized(lock) {
            if (released.get()) return
            val size = RotationPlanner.plan(geometry.widthPx, geometry.heightPx)
            if (size.width == config.width && size.height == config.height) return
            try {
                config = config.copy(width = size.width, height = size.height)
                capture.resize(size.width, size.height)
                encoder?.close()
                val recreated = encoderFactory.create(config, capture)
                encoder = recreated
                val rotation = rotationChanged { orientation = geometry.orientation }
                writeMessage(mediaMessage { rotationChanged = rotation })
                writeMessage(mediaMessage { mediaFormat = config.toMediaFormat() })
                recreated.requestSyncFrame()
            } catch (_: IOException) {
                release()
            } catch (_: IllegalStateException) {
                release()
            }
        }
    }

    private fun release() {
        if (!released.compareAndSet(false, true)) return
        displayChanges.stop()
        val closing = encoder
        encoder = null
        try {
            closing?.close()
        } finally {
            try {
                capture.stop()
            } finally {
                stream.closeGracefully()
            }
        }
    }

    private fun pump() {
        while (true) {
            val current = encoder ?: return
            val buffer = current.nextOutput()
            if (buffer == null) {
                if (encoder === current) return
                continue
            }
            synchronized(lock) { if (encoder === current) send(current, buffer) }
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
