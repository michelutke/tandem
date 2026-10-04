package dev.tandem.feature.mirror

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** EncoderConfigBuilder E61-13 tests (`docs/planning/backlog/phase-6.yaml` E61-13's `tdd:` list). Plain JUnit5. */
class EncoderConfigBuilderTest {
    @Test
    fun encoderConfig_default1080pH264_cbrAt8Mbps() {
        val config = EncoderConfigBuilder.build(sdkInt = 30)

        assertEquals("video/avc", config.mimeType)
        assertEquals(1920, config.width)
        assertEquals(1080, config.height)
        assertEquals(EncoderBitrateMode.Cbr, config.bitrateMode)
        assertEquals(8_000_000, config.bitrateBitsPerSecond)
    }

    @Test
    fun encoderConfig_api30Device_setsLowLatencyAndRealtimePriority() {
        val config = EncoderConfigBuilder.build(sdkInt = 30)

        assertEquals(1, config.lowLatency)
        assertEquals(0, config.priority)
    }

    @Test
    fun encoderConfig_api29Device_omitsLowLatencyKey() {
        val config = EncoderConfigBuilder.build(sdkInt = 29)

        assertNull(config.lowLatency)
        assertEquals(0, config.priority)
    }

    @Test
    fun encoderConfig_h264_constrainedBaselineLevel41() {
        val config = EncoderConfigBuilder.build(sdkInt = 30)

        assertEquals(EncoderProfile.AvcConstrainedBaseline, config.profile)
        assertEquals(EncoderLevel.Avc41, config.level)
    }

    @Test
    fun encoderConfig_default_iFrameInterval2s() {
        val config = EncoderConfigBuilder.build(sdkInt = 30)

        assertEquals(2, config.iFrameIntervalSeconds)
    }
}
