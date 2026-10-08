package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.ManualPairingContext
import dev.tandem.core.crypto.ManualPairingSas
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Builds the `Commitment`/`Reveal` payloads behind the `RAWMANUAL` command (E73-05 mitm-lab manual
 * pairing scenarios): the real [ManualPairingSas] commitment over this process's real SPKI and the
 * session's real `cb`, but with a caller-chosen reveal -- so a scenario can send a `Reveal` the real
 * [dev.tandem.core.pairing.ManualPairingStateMachine] never would (before any `Commitment`, a wrong
 * nonce, or a Mac fingerprint prefix standing in for the nonce). Holds the nonce of the last
 * [commitment] only for the current raw session; never persisted.
 */
internal class RawManualPairing(
    private val random: SecureRandom = SecureRandom(),
) {
    private var nonce: ByteArray? = null

    /** A fresh nonce's commitment (role phone) over the session's SPKIs and [cb]; remembers the nonce. */
    fun commitment(
        macSpkiDer: ByteArray,
        phoneSpkiDer: ByteArray,
        cb: ByteArray,
    ): ByteArray {
        val fresh = ByteArray(ManualPairingSas.NONCE_BYTES).also(random::nextBytes)
        nonce = fresh
        return ManualPairingSas.commitment(
            ManualPairingSas.Role.PHONE,
            fresh,
            ManualPairingContext(macSpkiDer, phoneSpkiDer, cb),
        )
    }

    /**
     * The 16 bytes to reveal for [spec]: empty means the nonce [commitment] committed to (random if
     * none), `NONCE=<hex>` a literal value, `PREFIX` the first 16 bytes of the Mac's SPKI SHA-256 --
     * the fingerprint-prefix stand-in ADR-008 rejects. `null` for an unrecognised or mis-sized spec.
     */
    fun revealNonce(
        spec: String,
        macSpkiDer: ByteArray,
    ): ByteArray? =
        when {
            spec.isEmpty() -> nonce ?: ByteArray(ManualPairingSas.NONCE_BYTES).also(random::nextBytes)
            spec.equals("PREFIX", ignoreCase = true) -> {
                MessageDigest.getInstance("SHA-256").digest(macSpkiDer).copyOf(ManualPairingSas.NONCE_BYTES)
            }
            spec.startsWith("NONCE=", ignoreCase = true) -> {
                spec.substringAfter("=").decodeHexOrNull()?.takeIf { it.size == ManualPairingSas.NONCE_BYTES }
            }
            else -> null
        }

    fun reset() {
        nonce = null
    }

    private fun String.decodeHexOrNull(): ByteArray? {
        if (length % 2 != 0 || isEmpty()) return null
        return runCatching {
            ByteArray(length / 2) { i -> ((this[2 * i].digitToInt(16) shl 4) or this[2 * i + 1].digitToInt(16)).toByte() }
        }.getOrNull()
    }
}
