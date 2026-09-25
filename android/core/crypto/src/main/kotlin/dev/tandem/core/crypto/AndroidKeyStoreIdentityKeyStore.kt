package dev.tandem.core.crypto

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.spec.ECGenParameterSpec
import android.security.keystore.StrongBoxUnavailableException as PlatformStrongBoxUnavailableException

private const val ANDROID_KEY_STORE_PROVIDER = "AndroidKeyStore"

/**
 * Production `IdentityKeyStore` (E10-15) backed by the real `AndroidKeyStore`. Generates a
 * non-exportable, signing-only P-256 key per [KeyGenParameterSpec], requesting the security level
 * the caller asks for via [getOrCreate]'s `preferStrongBox`; the StrongBox-then-TEE retry policy
 * itself lives in `IdentityKeyProvider` (E10-01), which is written against `IdentityKeyStore` and
 * decides whether to retry, not this class. `setDigests(DIGEST_SHA256, DIGEST_NONE)` is mandatory:
 * Conscrypt signs the TLS 1.3 `CertificateVerify` via `NONEwithECDSA` over a pre-computed
 * transcript hash, and without `DIGEST_NONE` every client-cert handshake fails with an opaque I/O
 * error (spike E03-03, docs/spikes/android-sslsocket-keystore.md; normative in SPEC.md §1).
 */
class AndroidKeyStoreIdentityKeyStore : IdentityKeyStore {
    private val keyStore: KeyStore =
        KeyStore.getInstance(ANDROID_KEY_STORE_PROVIDER).apply { load(null) }

    override fun getOrCreate(
        alias: String,
        preferStrongBox: Boolean,
    ): KeyHandle {
        get(alias)?.let { return it }

        val spec =
            KeyGenParameterSpec
                .Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)
                .setIsStrongBoxBacked(preferStrongBox)
                .build()

        try {
            KeyPairGenerator
                .getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEY_STORE_PROVIDER)
                .apply { initialize(spec) }
                .generateKeyPair()
        } catch (unavailable: PlatformStrongBoxUnavailableException) {
            throw StrongBoxUnavailableException(unavailable)
        }

        return get(alias)
            ?: error("AndroidKeyStore did not persist alias $alias after key generation")
    }

    override fun get(alias: String): KeyHandle? {
        val privateKey = keyStore.getKey(alias, null) as? PrivateKey
        val publicKey = keyStore.getCertificate(alias)?.publicKey
        if (privateKey == null || publicKey == null) return null

        val keyInfo =
            KeyFactory
                .getInstance(privateKey.algorithm, ANDROID_KEY_STORE_PROVIDER)
                .getKeySpec(privateKey, KeyInfo::class.java)

        return KeyHandle(
            alias = alias,
            publicKey = publicKey,
            privateKey = privateKey,
            securityLevel = keyInfo.toSecurityLevel(),
            isHardwareBacked = keyInfo.isInsideSecureHardware,
        )
    }

    override fun delete(alias: String) {
        keyStore.deleteEntry(alias)
    }
}

private fun KeyInfo.toSecurityLevel(): SecurityLevel =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        when (securityLevel) {
            KeyProperties.SECURITY_LEVEL_STRONGBOX -> SecurityLevel.STRONGBOX
            KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> SecurityLevel.TRUSTED_ENVIRONMENT
            else -> SecurityLevel.SOFTWARE
        }
    } else if (isInsideSecureHardware) {
        SecurityLevel.TRUSTED_ENVIRONMENT
    } else {
        SecurityLevel.SOFTWARE
    }
