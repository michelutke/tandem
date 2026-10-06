package dev.tandem.feature.mirror

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.RequiresDevice
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** E61-04 manual gate: `codecCapabilitySource_hardwareDevice_reportsHardwareAvcEncoder`. */
@RunWith(AndroidJUnit4::class)
class CodecCapabilityInstrumentedTest {
    @Test
    @RequiresDevice
    fun codecCapabilitySource_hardwareDevice_reportsHardwareAvcEncoder() {
        val encoders = MediaCodecListCapabilitySource().encoders()

        assertTrue(encoders.any { it.codec == MirrorCodec.H264 && it.hardwareAccelerated })
    }
}
