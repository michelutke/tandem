package dev.tandem.feature.mirror

object CodecNegotiator {
    /** HEVC only when the phone has a hardware HEVC encoder and the Mac advertises HEVC decode (PRD F-9.1). */
    fun negotiate(
        source: CodecCapabilitySource,
        macDecoders: Set<MirrorCodec>,
    ): MirrorCodec {
        val hardwareHevcEncoder = source.encoders().any { it.codec == MirrorCodec.Hevc && it.hardwareAccelerated }
        return if (hardwareHevcEncoder && MirrorCodec.Hevc in macDecoders) MirrorCodec.Hevc else MirrorCodec.H264
    }
}
