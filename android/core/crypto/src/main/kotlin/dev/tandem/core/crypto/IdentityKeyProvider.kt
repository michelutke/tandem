package dev.tandem.core.crypto

import android.util.Log

private const val TAG = "IdentityKeyProvider"

/** Fixed alias for the phone's identity key (E10-01); never varies across app installs. */
const val IDENTITY_KEY_ALIAS = "tandem.identity.v1"

/**
 * StrongBox-then-TEE fallback policy for the phone identity key (E10-01). Written against
 * `IdentityKeyStore` (E10-15) only, so it is unit-tested with `SoftwareIdentityKeyStore`;
 * hardware properties of the real `AndroidKeyStoreIdentityKeyStore` are asserted separately by
 * `instrumented:`/`manual:` tests.
 *
 * [logSecurityLevel] is a seam for the one log line the StrongBox fallback must emit (naming the
 * resulting security level, never key material) so it is assertable from a plain JVM unit test
 * without a fake/mocked `android.util.Log`.
 */
class IdentityKeyProvider(
    private val keyStore: IdentityKeyStore,
    private val logSecurityLevel: (SecurityLevel) -> Unit = {
        Log.i(TAG, "identity key generated via StrongBox fallback, securityLevel=$it")
    },
) {
    /**
     * Returns the phone's identity key, generating it via StrongBox on first call. If StrongBox is
     * unavailable, retries exactly once without it (TEE). If that retry also fails, throws
     * [IdentityKeyError.GenerationFailed] without creating a key from any other source.
     */
    fun getOrCreateIdentityKey(alias: String = IDENTITY_KEY_ALIAS): KeyHandle =
        try {
            keyStore.getOrCreate(alias, preferStrongBox = true)
        } catch (expectedStrongBoxUnavailable: StrongBoxUnavailableException) {
            val fallback =
                try {
                    keyStore.getOrCreate(alias, preferStrongBox = false)
                } catch (teeFailure: IdentityKeyStoreException) {
                    throw IdentityKeyError.GenerationFailed(teeFailure)
                }
            logSecurityLevel(fallback.securityLevel)
            fallback
        }
}

sealed class IdentityKeyError(
    message: String,
    cause: Throwable,
) : Exception(message, cause) {
    class GenerationFailed(
        cause: Throwable,
    ) : IdentityKeyError("Identity key generation failed", cause)
}
