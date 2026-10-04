package dev.tandem.core.transport.media

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.mediaTicketGrant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.time.Instant

/**
 * E60-09 tdd:
 *   unit: androidMediaLifecycle_controlSessionDead_mediaConnectionClosedWithin1s
 *   unit: androidMediaLifecycle_newMirrorStartWhileActive_closesPriorBeforeDial
 * The real-Mac-server `integration:` test runs in the E15-15 JVM harness.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MediaConnectionLifecycleTest {
    private val address = CandidateAddress("127.0.0.1", 1)
    private val pin = PinSource { emptyList() }
    private val events = mutableListOf<String>()
    private val streams = mutableListOf<RecordingByteStream>()

    @Test
    fun androidMediaLifecycle_controlSessionDead_mediaConnectionClosedWithin1s() =
        runTest {
            val session = readySession()
            val lifecycle = lifecycle(session)
            lifecycle.start(address)

            session.emitState(ConnectionState.Failed(ConnectionFailure.Timeout))
            advanceTimeBy(1_000)

            assertEquals(listOf("dial", "close"), events)
            assertFalse(lifecycle.mirrorActive.value)
        }

    @Test
    fun androidMediaLifecycle_controlSessionClosed_mediaConnectionClosedWithin1s() =
        runTest {
            val session = readySession()
            val lifecycle = lifecycle(session)
            lifecycle.start(address)

            session.emitState(ConnectionState.Disconnected())
            advanceTimeBy(1_000)

            assertEquals(listOf("dial", "close"), events)
            assertFalse(lifecycle.mirrorActive.value)
        }

    @Test
    fun androidMediaLifecycle_newMirrorStartWhileActive_closesPriorBeforeDial() =
        runTest {
            val session = readySession()
            val lifecycle = lifecycle(session)
            lifecycle.start(address)
            session.emitIncoming(grant(TICKET_B))

            lifecycle.start(address)

            assertEquals(listOf("dial", "close", "dial"), events)
            assertTrue(lifecycle.mirrorActive.value)
        }

    @Test
    fun androidMediaLifecycle_stop_closesMediaConnectionAndKeepsControlSession() =
        runTest {
            val session = readySession()
            val lifecycle = lifecycle(session)
            lifecycle.start(address)

            lifecycle.stop()

            assertEquals(listOf("dial", "close"), events)
            assertFalse(lifecycle.mirrorActive.value)
            assertInstanceOf(ConnectionState.Ready::class.java, session.state.value)
        }

    @Test
    fun androidMediaLifecycle_controlDeathAfterRestart_closesNewConnectionOnce() =
        runTest {
            val session = readySession()
            val lifecycle = lifecycle(session)
            lifecycle.start(address)
            session.emitIncoming(grant(TICKET_B))
            lifecycle.start(address)

            session.emitState(ConnectionState.Disconnected())
            advanceTimeBy(1_000)

            assertEquals(listOf("dial", "close", "dial", "close"), events)
            assertEquals(2, streams.size)
        }

    private fun readySession() =
        FakeTandemSession().also {
            it.emitState(ConnectionState.Ready(Instant.EPOCH))
            it.emitIncoming(grant(TICKET_A))
        }

    private fun grant(ticket: ByteArray) =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            mediaTicketGrant = mediaTicketGrant { this.ticket = ByteString.copyFrom(ticket) }
        }

    private fun TestScope.lifecycle(session: FakeTandemSession): MediaConnectionLifecycle {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val factory =
            MediaStreamFactory { _, _ ->
                events += "dial"
                RecordingByteStream().also { streams += it }
            }
        val dialer = MediaDialer(session, factory, pin, { testScheduler.currentTime }, dispatcher)
        return MediaConnectionLifecycle(session, dialer, CoroutineScope(dispatcher))
    }

    private inner class RecordingByteStream : ByteStream {
        override val input = ByteArrayInputStream(ByteArray(0))
        override val output = ByteArrayOutputStream()

        override fun closeGracefully() = Unit

        override fun closeAbruptly() {
            events += "close"
        }
    }

    private companion object {
        val TICKET_A = ByteArray(32) { 1 }
        val TICKET_B = ByteArray(32) { 2 }
    }
}
