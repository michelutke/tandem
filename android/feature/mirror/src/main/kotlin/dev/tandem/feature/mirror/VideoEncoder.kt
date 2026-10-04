package dev.tandem.feature.mirror

import android.view.Surface
import java.io.Closeable

/** One MediaCodec output buffer, copied out so the codec buffer can be released immediately. */
class EncodedBuffer(
    val data: ByteArray,
    val ptsMicros: Long,
    val isKeyFrame: Boolean,
    val isCodecConfig: Boolean,
)

/** The encoder seam (E61-03): the real adapter wraps `MediaCodec`, tests use a recording fake. */
interface VideoEncoder : Closeable {
    fun requestSyncFrame()

    fun setBitrate(bitsPerSecond: Int)

    /** Blocks until the next output buffer; returns null once the encoder is closed or ended. */
    fun nextOutput(): EncodedBuffer?
}

fun interface EncoderFactory {
    /** Builds and starts an encoder for [config]; the real factory hands its input surface to [capture]. */
    fun create(
        config: EncoderConfig,
        capture: CaptureSource,
    ): VideoEncoder
}

/** The capture seam (E61-03): MediaProjection + VirtualDisplay rendering into the encoder's input surface. */
interface CaptureSource {
    fun start(surface: Surface)

    fun stop()
}
