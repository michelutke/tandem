package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.harness.jvmclient.testserver.AcceptAnyTrustManager
import dev.tandem.harness.jvmclient.testserver.TestIdentity
import dev.tandem.harness.jvmclient.testserver.TestServerKeyManager
import dev.tandem.harness.jvmclient.testserver.TestTlsServer
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.net.InetAddress
import java.nio.file.Files
import java.time.Clock
import java.util.concurrent.TimeUnit

/**
 * E15-21 tdd: integration: jvmHarnessClient_opensslServerPeer_completesMutualTls13Handshake
 *
 * Runs against [TestTlsServer], a real Conscrypt `SSLServerSocket` on `127.0.0.1` — an in-process
 * JVM TLS peer standing in for the backlog's original `openssl s_server` acceptance target,
 * following the same test-server pattern `core/transport`'s own E12-04 tests use (per this
 * issue's actual coder-task scope: an in-process peer, not a shelled-out `openssl` binary).
 * Exercises the harness's real production wiring end to end: [PersistentIdentityKeyStore] +
 * [IdentityKeyManager] (the client identity), [PinningTrustManager] pinned to the server's real
 * SPKI fingerprint, and [SslClientFactory] (the TLS 1.3 client) — everything but the fake server
 * itself is the same code the harness CLI's `CONNECT` command runs.
 */
class HarnessClientTlsIntegrationTest {
    @Test
    fun jvmHarnessClient_opensslServerPeer_completesMutualTls13Handshake() {
        val identityFile = Files.createTempFile("harness-client-tls-test", ".bin").toFile().apply { delete() }
        val identityKeyStore = PersistentIdentityKeyStore(Clock.systemUTC(), identityFile)
        identityKeyStore.getOrCreate(PersistentIdentityKeyStore.IDENTITY_ALIAS, preferStrongBox = false)
        val clientKeyManager = IdentityKeyManager(identityKeyStore, PersistentIdentityKeyStore.IDENTITY_ALIAS)

        val serverIdentity = TestIdentity("server")
        val serverFingerprint = spkiFingerprint(serverIdentity.certificate.publicKey.encoded)
        val server = TestTlsServer(TestServerKeyManager(serverIdentity), AcceptAnyTrustManager())

        server.use {
            val resultFuture = server.acceptOnce()
            val pinSource = PinSource { listOf(serverFingerprint) }
            val factory =
                SslClientFactory(clientKeyManager, PinningTrustManager(pinSource), JvmConscryptSessionTicketDisabler())
            val socket = factory.createSocket()

            factory.connect(socket, InetAddress.getByName("127.0.0.1"), server.port).use { }

            val result = resultFuture.get(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            assertNull(result.handshakeError, "expected a completed mTLS handshake, got: ${result.handshakeError}")
            assertEquals(clientKeyManager.getCertificateChain(alias = null).single(), result.clientCertificate)
        }
    }

    private companion object {
        const val TIMEOUT_SECONDS = 5L
    }
}
