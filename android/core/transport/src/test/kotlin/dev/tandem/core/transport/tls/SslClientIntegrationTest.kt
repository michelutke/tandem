package dev.tandem.core.transport.tls

import dev.tandem.core.transport.testserver.AcceptAnyTrustManager
import dev.tandem.core.transport.testserver.ClientHelloCapturingProxy
import dev.tandem.core.transport.testserver.EXTENSION_TYPE_EARLY_DATA
import dev.tandem.core.transport.testserver.EXTENSION_TYPE_PRE_SHARED_KEY
import dev.tandem.core.transport.testserver.TestIdentity
import dev.tandem.core.transport.testserver.TestServerKeyManager
import dev.tandem.core.transport.testserver.TestTlsServer
import dev.tandem.core.transport.testserver.TestTlsServerConfig
import dev.tandem.core.transport.testserver.clientHelloExtensionTypes
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException

/**
 * E12-04 tdd:
 *   integration: sslClient_localhostServerTls12Only_handshakeFailsNoAppBytes
 *   integration: sslClient_localhostServerRequiresClientAuth_receivesKeyManagerCert
 *   integration: sslClient_serverIssuesTickets_secondClientHelloHasNoPsk
 *   integration: sslClient_serverSelectsNoAlpn_handshakeFails
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
            // can be inspected on the wire for a `pre_shared_key`/`early_data` extension.
            ClientHelloCapturingProxy(server.port).use { proxy ->
                proxy.start()
                val resultFuture = server.acceptOnce()
                val factory = clientFactory(clientIdentity)
                val socket = factory.createSocket()
                factory.connect(socket, localhost, proxy.port).use { }

                val result = resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                assertNull(result.handshakeError, "expected connection 2 to complete a full handshake")

                proxy.awaitRelayFinished(TIMEOUT_SECONDS)
                val record = proxy.capturedClientHelloRecord ?: error("no ClientHello was captured on the wire")
                val extensionTypes = clientHelloExtensionTypes(record)

                assertFalse(EXTENSION_TYPE_PRE_SHARED_KEY in extensionTypes, "must not offer pre_shared_key")
                assertFalse(EXTENSION_TYPE_EARLY_DATA in extensionTypes, "must not offer early_data")
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

    private fun clientFactory(identity: TestIdentity = TestIdentity("client")): SslClientFactory =
        SslClientFactory(identity.keyManager, AcceptAnyTrustManager(), ConscryptSessionTicketDisabler())

    private companion object {
        const val TIMEOUT_SECONDS = 5L
    }
}
