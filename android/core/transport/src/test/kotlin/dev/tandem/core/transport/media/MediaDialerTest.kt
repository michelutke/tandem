package dev.tandem.core.transport.media

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.testserver.AcceptAnyTrustManager
import dev.tandem.core.transport.testserver.TestIdentity
import dev.tandem.core.transport.testserver.TestServerKeyManager
import dev.tandem.core.transport.testserver.TestTlsServer
import dev.tandem.core.transport.testserver.TestTlsServerConfig
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.core.transport.tls.ConscryptSessionTicketDisabler
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.MediaHello
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.mediaTicketGrant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * E60-02 tdd:
 *   unit: mediaDialer_mirrorStart_sendsMediaHelloWithIssuedTicketAsFirstFrame
 *   unit: mediaDialer_trustEvaluation_usesControlSessionPinnedFingerprint
 *   unit: mediaDialer_serverFingerprintDiffersFromPin_abortsBeforeMediaHello
 * plus ticket expiry / fresh-ticket-per-dial handling (SPEC.md #media-ticket) and a loopback-TLS
 * success path. The mismatch test runs real TLS against `TestTlsServer`; the real-Mac-server
 * `integration:` test runs in the E15-15 JVM harness.
 */
class MediaDialerTest {
    private val address = CandidateAddress("127.0.0.1", 1)
    private val pin = PinSource { listOf(spkiFingerprint(TestIdentity("pinned").certificate.publicKey.encoded)) }

    @Test
    fun mediaDialer_mirrorStart_sendsMediaHelloWithIssuedTicketAsFirstFrame() =
        runBlocking {
            val session = sessionIssuing(TICKET_A)
            val stream = RecordingByteStream()

            val result = dialer(session, { _, _ -> stream }).dial(address, SESSION_ID)

            assertInstanceOf(MediaDialResult.Connected::class.java, result)
            assertEquals(1, session.sentFrames.size)
            assertTrue(session.sentFrames.single().hasRequestMediaTicket())
            val written = stream.written.toByteArray()
            val bodyLength = ByteBuffer.wrap(written).int
            assertEquals(written.size - 4, bodyLength)
            assertEquals(
                ByteString.copyFrom(TICKET_A),
                MediaHello.parseFrom(written.copyOfRange(4, written.size)).ticket,
            )
            assertEquals(SESSION_ID, MediaHello.parseFrom(written.copyOfRange(4, written.size)).mirrorSessionId)
        }

    @Test
    fun mediaDialer_trustEvaluation_usesControlSessionPinnedFingerprint() =
        runBlocking {
            var received: PinSource? = null
            val factory =
                MediaStreamFactory { _, source ->
                    received = source
                    RecordingByteStream()
                }

            dialer(sessionIssuing(TICKET_A), factory).dial(address, SESSION_ID)

            assertSame(pin, received)
        }

    @Test
    fun mediaDialer_serverFingerprintDiffersFromPin_abortsBeforeMediaHello() {
        val server = TestTlsServer(TestServerKeyManager(TestIdentity("other-server")), AcceptAnyTrustManager())
        server.use {
            val serverResult = server.acceptOnce()
            val factory =
                PinnedTlsMediaStreamFactory(TestIdentity("client").keyManager, ConscryptSessionTicketDisabler())

            val result =
                runBlocking {
                    dialer(
                        sessionIssuing(TICKET_A),
                        factory,
                    ).dial(CandidateAddress("127.0.0.1", server.port), SESSION_ID)
                }

            assertEquals(MediaDialResult.PinMismatch, result)
            assertEquals(0, serverResult.get(TIMEOUT_SECONDS, TimeUnit.SECONDS).applicationBytesReceived)
        }
    }

    @Test
    fun mediaDialer_serverFingerprintMatchesPin_helloReachesServer() {
        val serverIdentity = TestIdentity("pinned-server")
        val server =
            TestTlsServer(
                TestServerKeyManager(serverIdentity),
                AcceptAnyTrustManager(),
                TestTlsServerConfig(requireClientAuth = true),
            )
        server.use {
            val serverResult = server.acceptOnce()
            val factory =
                PinnedTlsMediaStreamFactory(TestIdentity("client").keyManager, ConscryptSessionTicketDisabler())
            val matchingPin = PinSource { listOf(spkiFingerprint(serverIdentity.certificate.publicKey.encoded)) }

            val result =
                runBlocking {
                    dialer(
                        sessionIssuing(TICKET_A),
                        factory,
                        matchingPin,
                    ).dial(CandidateAddress("127.0.0.1", server.port), SESSION_ID)
                }

            assertInstanceOf(MediaDialResult.Connected::class.java, result)
            assertEquals(
                4 + 2 + TICKET_A.size + 2 + SESSION_ID.size(),
                serverResult.get(TIMEOUT_SECONDS, TimeUnit.SECONDS).applicationBytesReceived,
            )
            (result as MediaDialResult.Connected).stream.close()
        }
    }

    @Test
    fun mediaDialer_ticketDeadlinePassedBeforeDial_returnsExpiredWithoutDialing() =
        runBlocking {
            var dialed = false
            val times = ArrayDeque(listOf(0L, 30_000L))
            val clock = ElapsedRealtimeSource { times.removeFirst() }

            val result =
                dialer(sessionIssuing(TICKET_A), { _, _ ->
                    dialed = true
                    RecordingByteStream()
                }, elapsedRealtime = clock).dial(address, SESSION_ID)

            assertEquals(MediaDialResult.TicketExpired, result)
            assertTrue(!dialed)
        }

    @Test
    fun mediaDialer_secondDial_requestsAndPresentsFreshTicket() =
        runBlocking {
            val session = sessionIssuing(TICKET_A)
            val streams = mutableListOf<RecordingByteStream>()
            val dialer = dialer(session, { _, _ -> RecordingByteStream().also { streams += it } })

            dialer.dial(address, SESSION_ID)
            session.emitIncoming(grantEnvelope(TICKET_B))
            dialer.dial(address, SESSION_ID)

            assertEquals(2, session.sentFrames.count { it.hasRequestMediaTicket() })
            val tickets =
                streams.map {
                    MediaHello
                        .parseFrom(
                            it.written.toByteArray().copyOfRange(4, it.written.size()),
                        ).ticket
                        .toByteArray()
                }
            assertArrayEquals(TICKET_A, tickets[0])
            assertArrayEquals(TICKET_B, tickets[1])
        }

    @Test
    fun mediaDialer_cancelledDuringConnect_closesOpenedStream() =
        runBlocking {
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            val stream = RecordingByteStream()
            val factory =
                MediaStreamFactory { _, _ ->
                    entered.countDown()
                    release.await()
                    stream
                }
            val job =
                launch(Dispatchers.Default) {
                    dialer(sessionIssuing(TICKET_A), factory).dial(address, SESSION_ID)
                }
            assertTrue(entered.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))

            job.cancel()
            release.countDown()
            job.join()

            assertTrue(stream.closedAbruptly)
        }

    @Test
    fun mediaDialer_sendRequestFailsWithIoException_returnsTicketUnavailable() =
        runBlocking {
            val session = sessionIssuing(TICKET_A)
            session.failNextSend(IOException("broken pipe"))

            val result = dialer(session, { _, _ -> RecordingByteStream() }).dial(address, SESSION_ID)

            assertEquals(MediaDialResult.TicketUnavailable, result)
        }

    @Test
    fun mediaDialer_lateGrantFromTimedOutRequest_isNotConsumedByNextDial() =
        runBlocking {
            val session = FakeTandemSession()
            val streams = mutableListOf<RecordingByteStream>()
            val dialer =
                dialer(session, { _, _ -> RecordingByteStream().also { streams += it } }, grantTimeoutMillis = 50L)

            assertEquals(MediaDialResult.TicketUnavailable, dialer.dial(address, SESSION_ID))
            session.emitIncoming(grantEnvelope(TICKET_A))
            session.emitIncoming(grantEnvelope(TICKET_B))
            dialer.dial(address, SESSION_ID)

            val written = streams.single().written.toByteArray()
            assertArrayEquals(TICKET_B, MediaHello.parseFrom(written.copyOfRange(4, written.size)).ticket.toByteArray())
        }

    private fun sessionIssuing(ticket: ByteArray): FakeTandemSession =
        FakeTandemSession().also { it.emitIncoming(grantEnvelope(ticket)) }

    private fun grantEnvelope(ticket: ByteArray) =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            mediaTicketGrant = mediaTicketGrant { this.ticket = ByteString.copyFrom(ticket) }
        }

    private fun dialer(
        session: FakeTandemSession,
        factory: MediaStreamFactory,
        pinSource: PinSource = pin,
        elapsedRealtime: ElapsedRealtimeSource = ElapsedRealtimeSource { 0L },
        grantTimeoutMillis: Long = 5_000L,
    ) = MediaDialer(session, factory, pinSource, elapsedRealtime, Dispatchers.IO, grantTimeoutMillis)

    private class RecordingByteStream : ByteStream {
        val written = ByteArrayOutputStream()
        override val input = ByteArrayInputStream(ByteArray(0))
        override val output = written

        override fun closeGracefully() = Unit

        var closedAbruptly = false

        override fun closeAbruptly() {
            closedAbruptly = true
        }
    }

    private companion object {
        const val TIMEOUT_SECONDS = 5L
        val TICKET_A = ByteArray(32) { 1 }
        val SESSION_ID: ByteString = ByteString.copyFrom(ByteArray(16) { 5 })
        val TICKET_B = ByteArray(32) { 2 }
    }
}
