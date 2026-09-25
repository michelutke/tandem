package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.KeyPairGenerator
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.time.temporal.ChronoUnit
import javax.security.auth.x500.X500Principal
import javax.net.ssl.SSLEngine as JavaxSslEngine

private const val AUTH_TYPE = "ECDSA"
private val UNRELATED_SUBJECT = X500Principal("CN=Not The Identity Subject")

/**
 * [PinningTrustManager] tests (E12-05). Certs are built with the `testFixtures`
 * `buildSelfSignedCertificate` helper so these run entirely on the JVM, no AndroidKeyStore.
 */
class PinningTrustManagerTest {
    private val clock = TestClock(TestCoroutineScheduler())

    private fun freshP256KeyPair() =
        KeyPairGenerator
            .getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()

    private fun certFor(
        keyPair: java.security.KeyPair,
        subject: X500Principal = UNRELATED_SUBJECT,
        notBefore: Instant = clock.instant().minus(1, ChronoUnit.DAYS),
        notAfter: Instant = Instant.parse("9999-12-31T23:59:59Z"),
    ): X509Certificate =
        buildSelfSignedCertificate(
            keyPair.public,
            keyPair.private,
            IdentityCertSpec(
                subject = subject,
                notBefore = notBefore,
                notAfter = notAfter,
                serialNumber = java.math.BigInteger.ONE,
            ),
        )

    private fun pinSourceOf(vararg fingerprints: SpkiFingerprint): PinSource = PinSource { fingerprints.toList() }

    @Test
    fun trustManager_matchingSpkiUnrelatedSubject_accepted() {
        val keyPair = freshP256KeyPair()
        val cert = certFor(keyPair, subject = X500Principal("CN=Totally Unrelated"))
        val pin = spkiFingerprint(keyPair.public.encoded)
        val trustManager = PinningTrustManager(pinSourceOf(pin))

        trustManager.checkServerTrusted(arrayOf(cert), AUTH_TYPE)
    }

    @Test
    fun trustManager_mismatchedSpki_throwsCertificateException() {
        val presentedCert = certFor(freshP256KeyPair())
        val otherPin = spkiFingerprint(freshP256KeyPair().public.encoded)
        val trustManager = PinningTrustManager(pinSourceOf(otherPin))

        assertThrows(CertificateException::class.java) {
            trustManager.checkServerTrusted(arrayOf(presentedCert), AUTH_TYPE)
        }
    }

    @Test
    fun trustManager_noPinNoTrustRecord_throwsCertificateException() {
        val presentedCert = certFor(freshP256KeyPair())
        val trustManager = PinningTrustManager(PinSource { emptyList() })

        assertThrows(CertificateException::class.java) {
            trustManager.checkServerTrusted(arrayOf(presentedCert), AUTH_TYPE)
        }
    }

    @Test
    fun trustManager_checkServerTrusted_neverQueriesHostOrAddress() {
        val keyPair = freshP256KeyPair()
        val cert = certFor(keyPair)
        val pin = spkiFingerprint(keyPair.public.encoded)
        val trustManager = PinningTrustManager(pinSourceOf(pin))

        trustManager.checkServerTrusted(arrayOf(cert), AUTH_TYPE, NeverTouchedSocket())
        trustManager.checkServerTrusted(arrayOf(cert), AUTH_TYPE, NeverTouchedSslEngine())
    }

    /** A `java.net.Socket` whose address/host accessors fail the test if the code under test ever calls them. */
    private class NeverTouchedSocket : java.net.Socket() {
        override fun getInetAddress(): java.net.InetAddress = throw AssertionError("must not be queried")

        override fun getRemoteSocketAddress(): java.net.SocketAddress = throw AssertionError("must not be queried")
    }

    /** A [JavaxSslEngine] whose every method fails the test if the code under test ever calls it. */
    private class NeverTouchedSslEngine : JavaxSslEngine() {
        override fun getPeerHost(): String = throw AssertionError("must not be queried")

        override fun getPeerPort(): Int = throw AssertionError("must not be queried")

        override fun wrap(
            srcs: Array<out java.nio.ByteBuffer>,
            offset: Int,
            length: Int,
            dst: java.nio.ByteBuffer,
        ): javax.net.ssl.SSLEngineResult = throw AssertionError("must not be queried")

        override fun unwrap(
            src: java.nio.ByteBuffer,
            dsts: Array<out java.nio.ByteBuffer>,
            offset: Int,
            length: Int,
        ): javax.net.ssl.SSLEngineResult = throw AssertionError("must not be queried")

        override fun getDelegatedTask(): Runnable = throw AssertionError("must not be queried")

        override fun closeInbound() = throw AssertionError("must not be queried")

        override fun isInboundDone(): Boolean = throw AssertionError("must not be queried")

        override fun closeOutbound() = throw AssertionError("must not be queried")

        override fun isOutboundDone(): Boolean = throw AssertionError("must not be queried")

        override fun getSupportedCipherSuites(): Array<String> = throw AssertionError("must not be queried")

        override fun getEnabledCipherSuites(): Array<String> = throw AssertionError("must not be queried")

        override fun setEnabledCipherSuites(suites: Array<out String>?) = throw AssertionError("must not be queried")

        override fun getSupportedProtocols(): Array<String> = throw AssertionError("must not be queried")

        override fun getEnabledProtocols(): Array<String> = throw AssertionError("must not be queried")

        override fun setEnabledProtocols(protocols: Array<out String>?) = throw AssertionError("must not be queried")

        override fun getSession(): javax.net.ssl.SSLSession = throw AssertionError("must not be queried")

        override fun beginHandshake() = throw AssertionError("must not be queried")

        override fun getHandshakeStatus(): javax.net.ssl.SSLEngineResult.HandshakeStatus =
            throw AssertionError("must not be queried")

        override fun setUseClientMode(mode: Boolean) = throw AssertionError("must not be queried")

        override fun getUseClientMode(): Boolean = throw AssertionError("must not be queried")

        override fun setNeedClientAuth(need: Boolean) = throw AssertionError("must not be queried")

        override fun getNeedClientAuth(): Boolean = throw AssertionError("must not be queried")

        override fun setWantClientAuth(want: Boolean) = throw AssertionError("must not be queried")

        override fun getWantClientAuth(): Boolean = throw AssertionError("must not be queried")

        override fun setEnableSessionCreation(flag: Boolean) = throw AssertionError("must not be queried")

        override fun getEnableSessionCreation(): Boolean = throw AssertionError("must not be queried")
    }

    @Test
    fun trustManager_expiredButPinnedCert_accepted() {
        val keyPair = freshP256KeyPair()
        val longAgo = Instant.parse("2000-01-01T00:00:00Z")
        val cert = certFor(keyPair, notBefore = longAgo, notAfter = longAgo.plus(1, ChronoUnit.DAYS))
        val pin = spkiFingerprint(keyPair.public.encoded)
        val trustManager = PinningTrustManager(pinSourceOf(pin))

        assertThrows(java.security.cert.CertificateExpiredException::class.java) { cert.checkValidity() }
        trustManager.checkServerTrusted(arrayOf(cert), AUTH_TYPE)
    }

    @Test
    fun trustManager_nonP256LeafKey_rejectedBeforePinCompare() {
        val rsaKeyPair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val signingKeyPair = freshP256KeyPair()
        val cert =
            buildSelfSignedCertificate(
                rsaKeyPair.public,
                signingKeyPair.private,
                IdentityCertSpec(
                    subject = UNRELATED_SUBJECT,
                    notBefore = clock.instant().minus(1, ChronoUnit.DAYS),
                    notAfter = Instant.parse("9999-12-31T23:59:59Z"),
                    serialNumber = java.math.BigInteger.ONE,
                ),
            )
        val trustManager = PinningTrustManager(PinSource { error("must not be called before the leaf-key check") })

        assertThrows(CertificateException::class.java) {
            trustManager.checkServerTrusted(arrayOf(cert), AUTH_TYPE)
        }
    }

    @Test
    fun trustManager_emptyChain_throwsCertificateException() {
        val trustManager = PinningTrustManager(PinSource { error("must not be called for an empty chain") })

        assertThrows(CertificateException::class.java) {
            trustManager.checkServerTrusted(arrayOf<X509Certificate>(), AUTH_TYPE)
        }
    }

    @Test
    fun trustManager_extraCertsAfterPinnedLeaf_ignoredAndAccepted() {
        val keyPair = freshP256KeyPair()
        val leaf = certFor(keyPair)
        val extra = certFor(freshP256KeyPair())
        val trustManager = PinningTrustManager(pinSourceOf(spkiFingerprint(keyPair.public.encoded)))

        trustManager.checkServerTrusted(arrayOf(leaf, extra), AUTH_TYPE)
    }

    @Test
    fun trustManager_pinnedCertBehindUnpinnedLeaf_throwsCertificateException() {
        val pinnedKeyPair = freshP256KeyPair()
        val unpinnedLeaf = certFor(freshP256KeyPair())
        val pinnedExtra = certFor(pinnedKeyPair)
        val trustManager = PinningTrustManager(pinSourceOf(spkiFingerprint(pinnedKeyPair.public.encoded)))

        assertThrows(CertificateException::class.java) {
            trustManager.checkServerTrusted(arrayOf(unpinnedLeaf, pinnedExtra), AUTH_TYPE)
        }
    }

    @Test
    fun trustManager_checkClientTrusted_alwaysThrows() {
        val trustManager = PinningTrustManager(pinSourceOf())
        val cert = certFor(freshP256KeyPair())

        assertThrows(CertificateException::class.java) { trustManager.checkClientTrusted(arrayOf(cert), AUTH_TYPE) }
        assertThrows(CertificateException::class.java) {
            trustManager.checkClientTrusted(arrayOf(cert), AUTH_TYPE, null as java.net.Socket?)
        }
        assertThrows(CertificateException::class.java) {
            trustManager.checkClientTrusted(arrayOf(cert), AUTH_TYPE, null as JavaxSslEngine?)
        }
    }

    @Test
    fun trustManager_getAcceptedIssuers_returnsEmptyArray() {
        val trustManager = PinningTrustManager(pinSourceOf())

        assertTrue(trustManager.acceptedIssuers.isEmpty())
    }
}
