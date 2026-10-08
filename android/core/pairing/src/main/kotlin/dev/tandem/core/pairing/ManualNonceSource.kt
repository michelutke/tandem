package dev.tandem.core.pairing

import java.security.SecureRandom

/**
 * Seam for the CSPRNG that mints the phone's per-attempt manual-pairing nonce (ADR-008). Tests
 * inject a fixed source; [SecureRandomManualNonceSource] is the production implementation.
 */
fun interface ManualNonceSource {
    /** A freshly generated 16-byte nonce, new on every call (never reused across attempts). */
    fun generateNonce(): ByteArray
}

class SecureRandomManualNonceSource(
    private val random: SecureRandom = SecureRandom(),
) : ManualNonceSource {
    override fun generateNonce(): ByteArray = ByteArray(NONCE_BYTES).also(random::nextBytes)

    private companion object {
        const val NONCE_BYTES = 16
    }
}
