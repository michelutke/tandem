package dev.tandem.core.transport.tls

import dev.tandem.core.transport.testserver.AcceptAnyTrustManager
import dev.tandem.core.transport.testserver.ClientHelloCapturingProxy
import dev.tandem.core.transport.testserver.EXTENSION_TYPE_EARLY_DATA
import dev.tandem.core.transport.testserver.EXTENSION_TYPE_PRE_SHARED_KEY
import dev.tandem.core.transport.testserver.EXTENSION_TYPE_SERVER_NAME
import dev.tandem.core.transport.testserver.TestIdentity
import dev.tandem.core.transport.testserver.TestServerKeyManager
import dev.tandem.core.transport.testserver.TestTlsServer
import dev.tandem.core.transport.testserver.TestTlsServerConfig
import dev.tandem.core.transport.testserver.clientHelloExtensionTypes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException
import kotlin.concurrent.thread

/**
 * E12-04 tdd:
 *   integration: sslClient_localhostServerTls12Only_handshakeFailsNoAppBytes
 *   integration: sslClient_localhostServerRequiresClientAuth_receivesKeyManagerCert
 *   integration: sslClient_serverIssuesTickets_secondClientHelloHasNoPsk
 *   integration: sslClient_serverSelectsNoAlpn_handshakeFails
 *   integration: sslSocketByteStream_closeAfterCloseGracefully_doesNotThrow
 *
 * Runs against [TestTlsServer], a real Conscrypt `SSLServerSocket` on `127.0.0.1` (JVM-only test
 * harness; production Android code never opens a listening socket, invariant 4).
 */
class SslClientIntegrationTest {
    private val localhost = InetAddress.getByName("127.0.0.1")

    @Test
    fun sslClient_localhostServerTls12Only_handshakeFailsNoAppBytes() {
        val server =
            TestTlsServer(
                TestServerKeyManager(TestIdentity("server")),
                AcceptAnyTrustManager(),
                TestTlsServerConfig(enabledProtocols = arrayOf("TLSv1.2")),
            )
        server.use {
            val resultFuture = server.acceptOnce()
            val factory = clientFactory()
            val socket = factory.createSocket()

            assertThrows(SSLHandshakeException::class.java) {
                factory.connect(socket, localhost, server.port)
            }

            val result = resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            assertEquals(0, result.applicationBytesReceived)
        }
    }

    @Test
    fun sslClient_localhostServerRequiresClientAuth_receivesKeyManagerCert() {
        val clientIdentity = TestIdentity("client")
        val server =
            TestTlsServer(
                TestServerKeyManager(TestIdentity("server")),
                AcceptAnyTrustManager(),
                TestTlsServerConfig(requireClientAuth = true),
            )
        server.use {
            val resultFuture = server.acceptOnce()
            val factory = clientFactory(clientIdentity)
            val socket = factory.createSocket()
            factory.connect(socket, localhost, server.port).use { }

            val result = resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            assertEquals(clientIdentity.certificate, result.clientCertificate)
        }
    }

    @Test
    fun sslClient_serverIssuesTickets_secondClientHelloHasNoPsk() {
        val clientIdentity = TestIdentity("client")
        val server = TestTlsServer(TestServerKeyManager(TestIdentity("server")), AcceptAnyTrustManager())
        server.use {
            // Connection 1: an ordinary handshake, on which the server may issue a session ticket.
            run {
                val resultFuture = server.acceptOnce()
                val factory = clientFactory(clientIdentity)
                val socket = factory.createSocket()
                factory.connect(socket, localhost, server.port).use { }
                resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            }

            // Connection 2: a FRESH client (fresh SSLContext per `SslClientFactory.createSocket`,
            // no shared session cache) dialed through a byte-capturing proxy so the raw ClientHello
            // can be inspected on the wire for a `pre_shared_key`/`early_data` extension. Dialing
            // with `InetAddress.getByName("localhost")` (a hostname-bearing address, unlike
            // `localhost` above which was built from a literal IP) proves `SslClientFactory` strips
            // the hostname before connecting, so Conscrypt never emits a `server_name` extension.
            ClientHelloCapturingProxy(server.port).use { proxy ->
                proxy.start()
                val resultFuture = server.acceptOnce()
                val factory = clientFactory(clientIdentity)
                val socket = factory.createSocket()
                factory.connect(socket, InetAddress.getByName("localhost"), proxy.port).use { }

                val result = resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                assertNull(result.handshakeError, "expected connection 2 to complete a full handshake")

                proxy.awaitRelayFinished(TIMEOUT_SECONDS)
                val record = proxy.capturedClientHelloRecord ?: error("no ClientHello was captured on the wire")
                val extensionTypes = clientHelloExtensionTypes(record)

                assertFalse(EXTENSION_TYPE_PRE_SHARED_KEY in extensionTypes, "must not offer pre_shared_key")
                assertFalse(EXTENSION_TYPE_EARLY_DATA in extensionTypes, "must not offer early_data")
                assertFalse(EXTENSION_TYPE_SERVER_NAME in extensionTypes, "must not offer server_name (no SNI)")
            }
        }
    }

    @Test
    fun sslClient_serverSelectsNoAlpn_handshakeFails() {
        val server =
            TestTlsServer(
                TestServerKeyManager(TestIdentity("server")),
                AcceptAnyTrustManager(),
                TestTlsServerConfig(alpnProtocols = arrayOf("other/1")),
            )
        server.use {
            val resultFuture = server.acceptOnce()
            val factory = clientFactory()
            val socket = factory.createSocket()

            // The underlying TLS stack completes the cryptographic handshake even though the two
            // ALPN lists don't overlap (it just leaves the protocol unselected); SslClientFactory
            // adds the explicit post-handshake check SPEC.md requires and fails closed itself.
            assertThrows(SSLHandshakeException::class.java) {
                factory.connect(socket, localhost, server.port)
            }

            val result = resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            assertEquals(0, result.applicationBytesReceived)
        }
    }

    @Test
    fun sslSocketByteStream_closeAfterCloseGracefully_doesNotThrow() {
        val server = TestTlsServer(TestServerKeyManager(TestIdentity("server")), AcceptAnyTrustManager())
        server.use {
            val resultFuture = server.acceptOnce()
            val factory = clientFactory()
            val socket = factory.createSocket()
            val stream = factory.connect(socket, localhost, server.port)

            stream.closeGracefully()
            assertDoesNotThrow { stream.close() }

            resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        }
    }

    @Test
    fun sslClientFactory_serverDripsHandshakeBytes_failsWithinTotalDeadline() {
        val serverSocket = ServerSocket(0, 1, localhost)
        val dripper =
            thread(isDaemon = true) {
                runCatching {
                    serverSocket.accept().use { accepted ->
                        accepted.getInputStream().read(ByteArray(CLIENT_HELLO_READ_BYTES))
                        val header = byteArrayOf(0x16, 0x03, 0x03, 0x40, 0x00)
                        val out = accepted.getOutputStream()
                        repeat(DRIP_COUNT) { index ->
                            out.write(if (index < header.size) header[index].toInt() else 0)
                            out.flush()
                            Thread.sleep(DRIP_INTERVAL_MILLIS)
                        }
                    }
                }
            }
        val factory = clientFactory()
        val socket = factory.createSocket()

        val startedAt = System.nanoTime()
        assertThrows(IOException::class.java) {
            factory.connect(socket, localhost, serverSocket.localPort, handshakeTimeoutMillis = TOTAL_DEADLINE_MILLIS)
        }
        val elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

        assertTrue(elapsedMillis < TOTAL_DEADLINE_MILLIS + DEADLINE_SLACK_MILLIS, "failed after $elapsedMillis ms")
        assertTrue(socket.isClosed)
        serverSocket.close()
        dripper.interrupt()
    }

    @Test
    fun sslClientFactory_dialCancelledWhileServerSilent_returnsPromptlyAndClosesSocket() {
        val serverSocket = ServerSocket(0, 1, localhost)
        val factory = clientFactory()
        val socket = factory.createSocket()

        val elapsedMillis =
            runBlocking {
                val dial =
                    launch(Dispatchers.IO) {
                        factory.connectCancellable(socket, localhost, serverSocket.localPort, Dispatchers.IO)
                    }
                delay(CANCEL_AFTER_MILLIS)
                val cancelledAt = System.nanoTime()
                dial.cancelAndJoin()
                TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - cancelledAt)
            }

        assertTrue(elapsedMillis < CANCEL_RETURN_MILLIS, "cancel took $elapsedMillis ms")
        assertTrue(socket.isClosed)
        serverSocket.close()
    }

    private fun clientFactory(identity: TestIdentity = TestIdentity("client")): SslClientFactory =
        SslClientFactory(identity.keyManager, AcceptAnyTrustManager(), ConscryptSessionTicketDisabler())

    private companion object {
        const val TIMEOUT_SECONDS = 5L
        const val TOTAL_DEADLINE_MILLIS = 1_000
        const val DEADLINE_SLACK_MILLIS = 800
        const val CANCEL_AFTER_MILLIS = 300L
        const val CANCEL_RETURN_MILLIS = 2_000L
        const val DRIP_COUNT = 40
        const val DRIP_INTERVAL_MILLIS = 250L
        const val CLIENT_HELLO_READ_BYTES = 16
    }
}
