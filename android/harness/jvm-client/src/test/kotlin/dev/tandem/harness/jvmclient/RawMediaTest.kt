package dev.tandem.harness.jvmclient

import dev.tandem.protocol.v1.MediaHello
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.ByteBuffer

/** E60-05: the raw `MediaHello` frame builder and `MEDIAOPEN` argument parser. */
class RawMediaTest {
    private val ticket = ByteArray(32) { it.toByte() }

    @Test
    fun rawMedia_helloFrame_lengthPrefixedMediaHelloWithGivenTicketAndSessionId() {
        val frame = RawMedia.helloFrame(ticket, ByteArray(16) { 7 })

        assertEquals(frame.size - 4, ByteBuffer.wrap(frame).int)
        val hello = MediaHello.parseFrom(frame.copyOfRange(4, frame.size))
        assertArrayEquals(ticket, hello.ticket.toByteArray())
        assertEquals(16, hello.mirrorSessionId.size())
    }

    @Test
    fun rawMedia_helloFrameWithoutTicket_ticketAbsent() {
        val frame = RawMedia.helloFrame(null)

        assertTrue(MediaHello.parseFrom(frame.copyOfRange(4, frame.size)).ticket.isEmpty)
    }

    @Test
    fun rawMedia_parsePresentation_recognisesKeywordsAndHex() {
        assertEquals(MediaPresentation.NoTicket, RawMedia.parsePresentation("none"))
        assertEquals(MediaPresentation.Silent, RawMedia.parsePresentation("SILENT"))
        assertArrayEquals(byteArrayOf(0x0a, 0xff.toByte()), (RawMedia.parsePresentation("0aff") as MediaPresentation.Ticket).bytes)
        assertNull(RawMedia.parsePresentation("xyz"))
    }
}
