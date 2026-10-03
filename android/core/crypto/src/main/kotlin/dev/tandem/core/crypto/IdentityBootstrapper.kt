package dev.tandem.core.crypto

import android.security.keystore.KeyPermanentlyInvalidatedException
import java.security.Signature

/** Arbitrary, non-secret payload for the sign+verify smoke test below; never logged or transmitted. */
private val SMOKE_TEST_PAYLOAD = "tandem-identity-smoke-test".toByteArray(Charsets.US_ASCII)

/** Matches the signing algorithm `IdentityCertSpec`'s self-signed certificate is issued under (E10-02). */
private const val SMOKE_TEST_SIGNATURE_ALGORITHM = "SHA256withECDSA"

/**
 * Identity lifecycle bootstrap (E10-04): on every app launch, [bootstrapIdentity] reuses an
 * existing, usable identity key (E10-01/E10-15) or generates one — eagerly on first launch, before
 * any pairing UI shows. "Usable" is verified by a real sign+verify smoke test, not just presence of
 * the alias, since AndroidKeyStore can retain an alias whose key is no longer usable.
 *
 * SPEC.md: regenerating the identity changes the phone's SPKI fingerprint (invariant 3), so every
 * Mac that previously paired against the old key no longer recognizes this phone. [requiresRePair]
 * surfaces that (invariant 5) until [notifyPairingSucceeded] is called after the next successful
 * pairing.
 *
 * [onIdentityReset] is a plain injected callback rather than a `Flow`/Turbine event stream: unlike
 * `core/testing`, `core/crypto`'s main source set has no `kotlinx-coroutines-core` dependency, so a
 * `SharedFlow`-typed property isn't available here without adding one. It follows the same
 * injected-callback seam `IdentityKeyProvider.logSecurityLevel` already uses in this package; tests
 * that want Turbine assertions wrap the callback in their own `MutableSharedFlow`.
 */
class IdentityBootstrapper(
    private val keyStore: IdentityKeyStore,
    private val activeAlias: ActiveIdentityAlias = ActiveIdentityAlias(),
    private val onIdentityReset: () -> Unit = {},
) {
    private val provider = IdentityKeyProvider(keyStore)

    /** True from an [IdentityReset] until [notifyPairingSucceeded] is called (SPEC.md, invariant 5). */
    @Volatile
    var requiresRePair: Boolean = false
        private set

    /**
     * Returns the phone's current identity, generating or regenerating it as needed. Safe to call
     * on every launch.
     */
    fun bootstrapIdentity(): KeyHandle {
        val existing = existingIdentity() ?: return resetIdentity()

        return try {
            verifyUsable(existing)
            existing
        } catch (expectedKeyPermanentlyInvalidated: KeyPermanentlyInvalidatedException) {
            resetIdentity()
        }
    }

    /** Call once a pairing completes successfully; clears [requiresRePair] until the next reset. */
    fun notifyPairingSucceeded() {
        requiresRePair = false
    }

    /**
     * The key under the active alias; if that key is gone but the original identity still exists,
     * falls back to it rather than ever replacing a valid identity.
     */
    private fun existingIdentity(): KeyHandle? =
        keyStore.get(activeAlias.current) ?: keyStore.get(IDENTITY_KEY_ALIAS)?.also {
            activeAlias.activate(IDENTITY_KEY_ALIAS)
        }

    private fun resetIdentity(): KeyHandle {
        keyStore.delete(activeAlias.current)
        keyStore.delete(IDENTITY_KEY_ALIAS)
        val handle = provider.getOrCreateIdentityKey(IDENTITY_KEY_ALIAS)
        activeAlias.activate(IDENTITY_KEY_ALIAS)
        requiresRePair = true
        onIdentityReset()
        return handle
    }

    private fun verifyUsable(handle: KeyHandle) {
        val signature =
            Signature.getInstance(SMOKE_TEST_SIGNATURE_ALGORITHM).apply {
                initSign(handle.privateKey)
                update(SMOKE_TEST_PAYLOAD)
            }
        val signed = signature.sign()

        val verifier =
            Signature.getInstance(SMOKE_TEST_SIGNATURE_ALGORITHM).apply {
                initVerify(handle.publicKey)
                update(SMOKE_TEST_PAYLOAD)
            }
        check(verifier.verify(signed)) { "Identity key smoke test failed to verify its own signature" }
    }
}
