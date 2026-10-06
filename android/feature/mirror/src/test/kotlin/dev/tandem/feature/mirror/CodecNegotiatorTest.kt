package dev.tandem.feature.mirror

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** CodecNegotiator E61-04 tests (`docs/planning/backlog/phase-6.yaml` E61-04's `tdd:` list). Plain JUnit5. */
class CodecNegotiatorTest {
    private class FakeCodecCapabilitySource(
        private val encoders: List<EncoderInfo>,
    ) : CodecCapabilitySource {
        override fun encoders(): List<EncoderInfo> = encoders
    }

    @Test
    fun codecNegotiator_bothAdvertiseHardwareHevc_selectsHevc() {
        val source =
            FakeCodecCapabilitySource(
                listOf(EncoderInfo(MirrorCodec.H264, true), EncoderInfo(MirrorCodec.Hevc, true)),
            )

        val codec = CodecNegotiator.negotiate(source, macDecoders = setOf(MirrorCodec.H264, MirrorCodec.Hevc))
        val config = EncoderConfigBuilder.build(codec = codec)

        assertEquals(MirrorCodec.Hevc, codec)
        assertEquals("video/hevc", config.mimeType)
        assertEquals(EncoderProfile.HevcMain, config.profile)
    }

    @Test
    fun codecNegotiator_macAdvertisesH264Only_selectsH264WithoutError() {
        val source =
            FakeCodecCapabilitySource(
                listOf(EncoderInfo(MirrorCodec.H264, true), EncoderInfo(MirrorCodec.Hevc, true)),
            )

        val codec = CodecNegotiator.negotiate(source, macDecoders = setOf(MirrorCodec.H264))

        assertEquals(MirrorCodec.H264, codec)
        assertEquals("video/avc", EncoderConfigBuilder.build(codec = codec).mimeType)
    }

    @Test
    fun codecNegotiator_androidHevcSoftwareOnly_selectsH264() {
        val source =
            FakeCodecCapabilitySource(
                listOf(EncoderInfo(MirrorCodec.H264, true), EncoderInfo(MirrorCodec.Hevc, false)),
            )

        val codec = CodecNegotiator.negotiate(source, macDecoders = setOf(MirrorCodec.H264, MirrorCodec.Hevc))

        assertEquals(MirrorCodec.H264, codec)
    }
}
