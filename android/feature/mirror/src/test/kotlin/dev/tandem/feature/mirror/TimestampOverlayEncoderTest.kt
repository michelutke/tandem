package dev.tandem.feature.mirror

import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File

/** E61-08 timestamp overlay encoder test against the fixture frame shared with the macOS decoder. */
class TimestampOverlayEncoderTest {
    @Test
    fun timestampOverlayEncoder_frameIndexAndClock_matchFixtureFramePixels() {
        val fixture = File(requireNotNull(System.getProperty("tandem.overlayFixture"))).readBytes()
        val (width, height, pixels) = parsePgm(fixture)

        val rendered = TimestampOverlayEncoder.render(FRAME_INDEX, CLOCK_MS, width, height)

        assertEquals(800, width)
        assertEquals(16, height)
        assertArrayEquals(pixels, rendered)
    }

    private fun parsePgm(bytes: ByteArray): Triple<Int, Int, ByteArray> {
        val headerLength = bytes.indices.filter { bytes[it] == '\n'.code.toByte() }[2] + 1
        val header = String(bytes, 0, headerLength, Charsets.US_ASCII)
        val fields = header.trim().split(Regex("\\s+"))
        assertEquals(listOf("P5", "800", "16", "255"), fields)
        return Triple(fields[1].toInt(), fields[2].toInt(), bytes.copyOfRange(header.length, bytes.size))
    }

    private companion object {
        const val FRAME_INDEX = 123456789L
        const val CLOCK_MS = 1700000123456L
    }
}
