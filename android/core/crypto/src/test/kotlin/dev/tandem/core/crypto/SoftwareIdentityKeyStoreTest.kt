package dev.tandem.core.crypto

import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.AlgorithmParameters
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec

class SoftwareIdentityKeyStoreTest {
    private val clock = TestClock(TestCoroutineScheduler())
    private val secp256r1: ECParameterSpec =
        AlgorithmParameters
            .getInstance("EC")
            .apply { init(ECGenParameterSpec("secp256r1")) }
            .getParameterSpec(ECParameterSpec::class.java)

    @Test
    fun softwareKeyStore_generateP256_publicKeyIsSecp256r1() {
        val handle = SoftwareIdentityKeyStore(clock).getOrCreate("alias", preferStrongBox = true)

        val params = (handle.publicKey as ECPublicKey).params
        assertEquals(secp256r1.curve, params.curve)
        assertEquals(secp256r1.order, params.order)
        assertEquals(secp256r1.generator, params.generator)
        assertEquals(SecurityLevel.SOFTWARE, handle.securityLevel)
        assertFalse(handle.isHardwareBacked)
    }

    @Test
    fun softwareKeyStore_signThenVerifyWithPublicKey_verifies() {
        val handle = SoftwareIdentityKeyStore(clock).getOrCreate("alias", preferStrongBox = false)
        val data = "tandem".toByteArray()

        val sha256Signature =
            Signature.getInstance("SHA256withECDSA").run {
                initSign(handle.privateKey)
                update(data)
                sign()
            }
        assertTrue(
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(handle.publicKey)
                update(data)
                verify(sha256Signature)
            },
        )

        // TLS 1.3 CertificateVerify signs a pre-computed transcript hash directly, via
        // NONEwithECDSA, not SHA256withECDSA over raw bytes (docs/spikes/android-sslsocket-keystore.md).
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        val noneSignature =
            Signature.getInstance("NONEwithECDSA").run {
                initSign(handle.privateKey)
                update(digest)
                sign()
            }
        assertTrue(
            Signature.getInstance("NONEwithECDSA").run {
                initVerify(handle.publicKey)
                update(digest)
                verify(noneSignature)
            },
        )
    }

    @Test
    fun softwareKeyStore_failNextGenerateStrongBox_throwsStrongBoxUnavailable() {
        val store = SoftwareIdentityKeyStore(clock)
        store.failNextGenerate(InjectedKeyStoreFailure.STRONGBOX_UNAVAILABLE)

        assertThrows(StrongBoxUnavailableException::class.java) {
            store.getOrCreate("alias", preferStrongBox = true)
        }

        // One-shot: the next call generates normally.
        val handle = store.getOrCreate("alias", preferStrongBox = false)
        assertEquals(SecurityLevel.SOFTWARE, handle.securityLevel)
    }

    @Test
    fun softwareKeyStore_failNextGenerateKeystoreCorrupted_throwsKeystoreCorrupted() {
        val store = SoftwareIdentityKeyStore(clock)
        store.failNextGenerate(InjectedKeyStoreFailure.KEYSTORE_CORRUPTED)

        assertThrows(KeystoreCorruptedException::class.java) {
            store.getOrCreate("alias", preferStrongBox = true)
        }

        assertNotNull(store.getOrCreate("alias", preferStrongBox = true))
    }

    @Test
    fun softwareKeyStore_getOrCreateCalledTwice_returnsSameKeyWithoutRegenerating() {
        val store = SoftwareIdentityKeyStore(clock)
        val first = store.getOrCreate("alias", preferStrongBox = true)
        val second = store.getOrCreate("alias", preferStrongBox = true)
        assertSame(first, second)
    }

    @Test
    fun softwareKeyStore_getMissingAlias_returnsNull() {
        assertNull(SoftwareIdentityKeyStore(clock).get("missing"))
    }

    @Test
    fun softwareKeyStore_deleteThenGetOrCreate_generatesDifferentKey() {
        val store = SoftwareIdentityKeyStore(clock)
        val first = store.getOrCreate("alias", preferStrongBox = true)
        store.delete("alias")
        val second = store.getOrCreate("alias", preferStrongBox = true)
        assertNotEquals(first.publicKey, second.publicKey)
    }

    @Test
    fun selfSignedCert_softwareKeyStore_publicKeyEqualsKeyHandlePublicKey() {
        val handle = SoftwareIdentityKeyStore(clock).getOrCreate("alias", preferStrongBox = true)

        assertEquals(handle.publicKey, handle.certificate.publicKey)
    }

    @Test
    fun selfSignedCert_signature_verifiesWithOwnPublicKey() {
        val handle = SoftwareIdentityKeyStore(clock).getOrCreate("alias", preferStrongBox = true)

        assertDoesNotThrow { handle.certificate.verify(handle.publicKey) }
    }
}
