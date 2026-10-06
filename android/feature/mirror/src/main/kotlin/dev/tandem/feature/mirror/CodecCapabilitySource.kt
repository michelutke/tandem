package dev.tandem.feature.mirror

import android.media.MediaCodecList

data class EncoderInfo(
    val codec: MirrorCodec,
    val hardwareAccelerated: Boolean,
)

/** Seam over `MediaCodecList`; unit tests supply a fake list. */
interface CodecCapabilitySource {
    fun encoders(): List<EncoderInfo>
}

class MediaCodecListCapabilitySource : CodecCapabilitySource {
    override fun encoders(): List<EncoderInfo> =
        MediaCodecList(MediaCodecList.REGULAR_CODECS)
            .codecInfos
            .filter { it.isEncoder }
            .flatMap { info ->
                MirrorCodec.entries
                    .filter { codec -> info.supportedTypes.any { it.equals(codec.mimeType, ignoreCase = true) } }
                    .map { EncoderInfo(it, info.isHardwareAccelerated) }
            }
}
