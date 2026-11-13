package dev.tandem.core.transport

import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameTooLargeException
import dev.tandem.core.protocol.multiplex.MultiplexerClose
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.heartbeat
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SendOrDropTest {
    @Test
    fun sendOrDrop_sessionOpen_sendsAndReturnsTrue() =
        runTest {
            val session = FakeTandemSession()

            assertTrue(session.sendOrDrop(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} })

            assertEquals(1, session.sentFrames.size)
        }

    @Test
    fun sendOrDrop_multiplexerClosed_returnsFalse() =
        runTest {
            val session = FakeTandemSession()
            session.failNextSend(MultiplexerClosedException(MultiplexerClose.PeerClosed))

            assertFalse(session.sendOrDrop(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} })
        }

    @Test
    fun sendOrDrop_frameTooLarge_returnsFalse() =
        runTest {
            val session = FakeTandemSession()
            session.failNextSend(FrameTooLargeException(FrameEncoder.MAX_ENVELOPE_BYTES + 1))

            assertFalse(session.sendOrDrop(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} })
        }

    @Test
    fun sendOrDrop_unrelatedFailure_propagates() =
        runTest {
            val session = FakeTandemSession()
            session.failNextSend(IllegalStateException("bug"))

            assertThrows(IllegalStateException::class.java) {
                runBlocking { session.sendOrDrop(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} } }
            }
        }
}
