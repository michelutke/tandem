package dev.tandem.app.mirror

import dev.tandem.protocol.v1.keyframeRequest
import dev.tandem.protocol.v1.mediaMessage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class MediaControlReaderTest {
    private fun frame(body: ByteArray): ByteArray =
        ByteBuffer
            .allocate(4 + body.size)
            .putInt(body.size)
            .put(body)
            .array()

    @Test
    fun mediaControlReader_keyframeRequest_routedToEncoder() {
        var requests = 0
        val bytes =
            ByteArrayOutputStream().apply {
                repeat(2) { write(frame(mediaMessage { keyframeRequest = keyframeRequest { } }.toByteArray())) }
            }

        MediaControlReader(ByteArrayInputStream(bytes.toByteArray())) { requests++ }.run()

        assertEquals(2, requests)
    }

    @Test
    fun mediaControlReader_oversizeFrame_returnsWithoutRouting() {
        var requests = 0
        val oversize = ByteBuffer.allocate(4).putInt(Int.MAX_VALUE).array()

        MediaControlReader(ByteArrayInputStream(oversize)) { requests++ }.run()

        assertEquals(0, requests)
    }
}
