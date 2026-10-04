package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.protocol.v1.KeyRotation
import java.security.SecureRandom

/**
 * The phone side of a Mac-initiated rotation behind the `RAWMACROTATION` command (E70-09 mitm-lab):
 * the unsolicited `RotationChallenge` a phone sends on every control session (SPEC.md #key-rotation,
 * D-74), and the check the real receiver makes on the Mac's `KeyRotation` -- both signatures over the
 * transcript built from the Mac key that authenticated this session, the new key and that challenge.
 * Pinning is deliberately not done here: the scenario shows what an *unacked* phone still trusts.
 */
internal object RawMacRotation {
    private const val CHALLENGE_BYTES = 32

    fun newChallenge(random: SecureRandom = SecureRandom()): ByteArray = ByteArray(CHALLENGE_BYTES).also(random::nextBytes)

    fun isValidOffer(
        macSpkiDer: ByteArray,
        challenge: ByteArray,
        offer: KeyRotation,
    ): Boolean =
        RotationProof.verify(
            oldSpkiDer = macSpkiDer,
            newSpkiDer = offer.newSpkiDer.toByteArray(),
            cb = challenge,
            sigOldKey = offer.sigOldKey.toByteArray(),
            sigNewKey = offer.sigNewKey.toByteArray(),
        )

    /** The new key's SPKI fingerprint in lowercase hex, as `-HarnessSeedTrust` and the Mac driver print it. */
    fun newKeyFingerprintHex(offer: KeyRotation): String =
        spkiFingerprint(offer.newSpkiDer.toByteArray()).bytes.joinToString(separator = "") { "%02x".format(it) }
}
