package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.time.temporal.ChronoUnit
import javax.security.auth.x500.X500Principal

/** [UnpinnedPeerTrustManager] (E73-03): accepts any pinnable P-256 leaf, nothing else, never a client. */
class UnpinnedPeerTrustManagerTest {
    private val clock = TestClock(TestCoroutineScheduler())

    private fun p256KeyPair(): KeyPair =
        KeyPairGenerator
            .getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()

    private fun certFor(keyPair: KeyPair): X509Certificate =
        buildSelfSignedCertificate(
            keyPair.public,
            keyPair.private,
            IdentityCertSpec(
                subject = X500Principal("CN=Unrelated"),
                notBefore = clock.instant().minus(1, ChronoUnit.DAYS),
                notAfter = clock.instant().plus(1, ChronoUnit.DAYS),
                serialNumber = BigInteger.ONE,
            ),
        )

    @Test
    fun unpinnedTrustManager_p256Leaf_accepted() {
        UnpinnedPeerTrustManager().checkServerTrusted(arrayOf(certFor(p256KeyPair())), "ECDSA")
    }

    @Test
    fun unpinnedTrustManager_emptyChain_rejected() {
        assertThrows(CertificateException::class.java) {
            UnpinnedPeerTrustManager().checkServerTrusted(emptyArray(), "ECDSA")
        }
    }

    @Test
    fun unpinnedTrustManager_clientChain_neverTrusted() {
        assertThrows(CertificateException::class.java) {
            UnpinnedPeerTrustManager().checkClientTrusted(arrayOf(certFor(p256KeyPair())), "ECDSA")
        }
    }
}
