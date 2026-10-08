package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.ManualPairingContext
import dev.tandem.core.crypto.ManualPairingSas
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.spec.ECGenParameterSpec

/** [RawManualPairing] (E73-05): the scenario scripts' manual `Commitment`/`Reveal` builder. */
class RawManualPairingTest {
    private val macSpki = spki()
    private val phoneSpki = spki()
    private val cb = ByteArray(32) { it.toByte() }
    private val context = ManualPairingContext(macSpki, phoneSpki, cb)

    private fun spki(): ByteArray =
        KeyPairGenerator
            .getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()
            .public.encoded

    @Test
    fun rawManual_defaultReveal_matchesTheCommittedNonce() {
        val raw = RawManualPairing()
        val commitment = raw.commitment(macSpki, phoneSpki, cb)

        val nonce = checkNotNull(raw.revealNonce("", macSpki))

        assertTrue(ManualPairingSas.verifyCommitment(commitment, ManualPairingSas.Role.PHONE, nonce, context))
    }

    @Test
    fun rawManual_prefixReveal_isFingerprintPrefixAndNeverVerifies() {
        val raw = RawManualPairing()
        val commitment = raw.commitment(macSpki, phoneSpki, cb)

        val prefix = checkNotNull(raw.revealNonce("PREFIX", macSpki))

        assertArrayEquals(MessageDigest.getInstance("SHA-256").digest(macSpki).copyOf(16), prefix)
        assertFalse(ManualPairingSas.verifyCommitment(commitment, ManualPairingSas.Role.PHONE, prefix, context))
    }

    @Test
    fun rawManual_literalAndMalformedNonceSpecs() {
        val raw = RawManualPairing()
        assertEquals(16, raw.revealNonce("NONCE=" + "ab".repeat(16), macSpki)?.size)
        assertNull(raw.revealNonce("NONCE=abcd", macSpki))
        assertNull(raw.revealNonce("BOGUS", macSpki))
    }
}
