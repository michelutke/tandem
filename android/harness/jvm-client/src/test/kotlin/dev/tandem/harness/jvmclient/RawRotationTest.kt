package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.spkiFingerprint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.time.Clock

/** E70-09: the raw `KeyRotation` builder signs the real transcript over the caller's `cb`. */
class RawRotationTest {
    private val identityKey =
        PersistentIdentityKeyStore(Clock.systemUTC(), Files.createTempFile("raw-rotation", ".bin").toFile().apply { delete() })
            .getOrCreate(PersistentIdentityKeyStore.IDENTITY_ALIAS, preferStrongBox = false)
    private val cb = ByteArray(32) { it.toByte() }

    @Test
    fun rawRotation_build_signaturesVerifyOverGivenCb() {
        val rotation = RawRotation(identityKey).build(cb, useHeldKey = false)

        assertTrue(
            RotationProof.verify(
                identityKey.publicKey.encoded,
                rotation.newSpkiDer.toByteArray(),
                cb,
                rotation.sigOldKey.toByteArray(),
                rotation.sigNewKey.toByteArray(),
            ),
        )
    }

    @Test
    fun rawRotation_buildForOtherCb_signaturesFailOnThisCb() {
        val rotation = RawRotation(identityKey).build(cb, useHeldKey = false)

        assertFalse(
            RotationProof.verify(
                identityKey.publicKey.encoded,
                rotation.newSpkiDer.toByteArray(),
                ByteArray(32) { 0 },
                rotation.sigOldKey.toByteArray(),
                rotation.sigNewKey.toByteArray(),
            ),
        )
    }

    @Test
    fun rawRotation_heldKey_newSpkiIsTheGeneratedKey() {
        val rawRotation = RawRotation(identityKey)
        val heldFingerprintHex = rawRotation.generateHeldKey()

        val rotation = rawRotation.build(cb, useHeldKey = true)

        val newFingerprintHex = spkiFingerprint(rotation.newSpkiDer.toByteArray()).bytes.joinToString("") { "%02x".format(it) }
        assertEquals(heldFingerprintHex, newFingerprintHex)
    }

    @Test
    fun rawRotation_heldKeyWrittenAsIdentity_reloadsWithHeldFingerprint() {
        val rawRotation = RawRotation(identityKey)
        val heldFingerprintHex = rawRotation.generateHeldKey()
        val file = Files.createTempFile("held-identity", ".bin").toFile()

        PersistentIdentityKeyStore.write(file, rawRotation.heldKeyHandle())
        val reloaded =
            PersistentIdentityKeyStore(Clock.systemUTC(), file)
                .getOrCreate(PersistentIdentityKeyStore.IDENTITY_ALIAS, preferStrongBox = false)

        val reloadedFingerprintHex = spkiFingerprint(reloaded.certificate.publicKey.encoded).bytes.joinToString("") { "%02x".format(it) }
        assertEquals(heldFingerprintHex, reloadedFingerprintHex)
    }
}
