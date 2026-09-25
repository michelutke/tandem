package dev.tandem.core.crypto

import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException
import java.math.BigInteger
import java.net.InetAddress
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.security.auth.x500.X500Principal

/**
 * `integration:` layer test (root CLAUDE.md "Testing" section) for E12-05: a real JVM TLS 1.3
 * handshake, plain JSSE (`SunJSSE`, no Conscrypt), between an in-process `SSLServerSocket`
 * presenting a self-signed cert the client never pinned, and [PinningTrustManager] as the
 * client's trust manager. No `integration:`-tagged JUnit convention or separate source set exists
 * yet elsewhere in this repo (checked: no `@Tag("integration")`, no `integrationTest` source
 * set), so this is a plain JUnit5 test in the `test` source set, matching the `unit:` tests above.
 */
class PinningTrustManagerIntegrationTest {
    @Test
    fun trustManager_localhostServerWrongCert_handshakeFailsZeroAppBytes() {
        val wrongCertKeyPair = freshP256KeyPair()
        val serverSocket = startTlsServer(wrongCertKeyPair, certFor(wrongCertKeyPair))
        val acceptExecutor = Executors.newSingleThreadExecutor()

        try {
            // Server accept-loop: reading application data only succeeds past a completed
            // handshake, so a read that throws or returns -1 (EOF) without ever completing proves
            // no application byte crossed the wire (the "0 application bytes" acceptance
            // criterion, phrased for the client side that actually fails the handshake here).
            val serverReadResult =
                acceptExecutor.submit<Int> {
                    serverSocket.accept().use { socket ->
                        try {
                            (socket as javax.net.ssl.SSLSocket).inputStream.read()
                        } catch (_: IOException) {
                            -1
                        }
                    }
                }

            val pinnedToADifferentKey = spkiFingerprint(freshP256KeyPair().public.encoded)
            val clientContext = SSLContext.getInstance("TLSv1.3")
            clientContext.init(null, arrayOf(PinningTrustManager(PinSource { listOf(pinnedToADifferentKey) })), null)

            clientContext.socketFactory
                .createSocket(InetAddress.getLoopbackAddress(), serverSocket.localPort)
                .use { clientSocket ->
                    assertThrows(IOException::class.java) {
                        (clientSocket as javax.net.ssl.SSLSocket).startHandshake()
                    }
                }

            val appBytesRead = serverReadResult.get(5, TimeUnit.SECONDS)
            assertTrue(appBytesRead == -1, "server must never read an application byte, got $appBytesRead")
        } finally {
            acceptExecutor.shutdownNow()
            serverSocket.close()
        }
    }

    private fun freshP256KeyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    private fun certFor(keyPair: KeyPair): X509Certificate =
        buildSelfSignedCertificate(
            keyPair.public,
            keyPair.private,
            IdentityCertSpec(
                subject = X500Principal("CN=Wrong Cert"),
                notBefore = Instant.now().minus(1, ChronoUnit.DAYS),
                notAfter = Instant.parse("9999-12-31T23:59:59Z"),
                serialNumber = BigInteger.ONE,
            ),
        )

    private fun startTlsServer(
        keyPair: KeyPair,
        cert: X509Certificate,
    ): SSLServerSocket {
        val password = "changeit".toCharArray()
        val keyStore =
            KeyStore.getInstance("PKCS12").apply {
                load(null, null)
                setKeyEntry("server", keyPair.private, password, arrayOf(cert))
            }

        val keyManagerFactory =
            KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(keyStore, password) }

        val serverContext =
            SSLContext.getInstance("TLSv1.3").apply { init(keyManagerFactory.keyManagers, null, null) }

        return serverContext.serverSocketFactory
            .createServerSocket(0, 50, InetAddress.getLoopbackAddress()) as SSLServerSocket
    }
}
