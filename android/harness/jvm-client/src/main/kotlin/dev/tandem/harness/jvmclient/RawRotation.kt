package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.KeyHandle
import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.protocol.v1.KeyRotation
import dev.tandem.protocol.v1.keyRotation
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.time.Clock

/**
 * Builds the `KeyRotation` frames behind the `RAWKEYGEN`/`RAWROTATE` commands (E70-09 mitm-lab
 * rotation scenarios): the real [RotationProof] transcript signed by this process's real identity
 * key (old key) and a new key, but over a caller-chosen `cb` -- so a scenario can replay a `cb` from
 * another session, which the real `RotationInitiator` never would. The new key is a fresh P-256 key
 * unless [generateHeldKey] pinned one earlier (a scenario seeds that key into the Mac's trust store
 * as "another paired peer" before asking for it as `newSpki`). Never persisted.
 */
internal class RawRotation(
    private val identityKey: KeyHandle,
) {
    private val heldKeyStore = SoftwareIdentityKeyStore(Clock.systemUTC())
    private var heldKey: KeyHandle? = null

    /** Generates and holds a new key; returns its SPKI fingerprint (the `-HarnessSeedTrust` fingerprint) in hex. */
    fun generateHeldKey(): String {
        val handle = heldKeyStore.getOrCreate(HELD_KEY_ALIAS, preferStrongBox = false)
        heldKey = handle
        return spkiFingerprint(handle.publicKey.encoded).bytes.joinToString(separator = "") { "%02x".format(it) }
    }

    /** The key [generateHeldKey] generated, with its certificate, so it can become a process's identity. */
    fun heldKeyHandle(): KeyHandle = requireNotNull(heldKey) { "no held key (RAWKEYGEN first)" }

    fun build(
        cb: ByteArray,
        useHeldKey: Boolean,
    ): KeyRotation {
        val newKey = if (useHeldKey) heldKeyHandle().let { KeyPair(it.publicKey, it.privateKey) } else newKeyPair()
        val oldSpki = identityKey.publicKey.encoded
        val newSpki = newKey.public.encoded
        val transcript = RotationProof.transcript(oldSpki, newSpki, cb)
        return keyRotation {
            newSpkiDer = ByteString.copyFrom(newSpki)
            sigOldKey = ByteString.copyFrom(sign(identityKey.privateKey, transcript))
            sigNewKey = ByteString.copyFrom(sign(newKey.private, transcript))
        }
    }

    private fun newKeyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").run {
            initialize(ECGenParameterSpec("secp256r1"))
            generateKeyPair()
        }

    private fun sign(
        key: PrivateKey,
        message: ByteArray,
    ): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(key)
            update(message)
            sign()
        }

    private companion object {
        const val HELD_KEY_ALIAS = "harness-held-key"
    }
}
