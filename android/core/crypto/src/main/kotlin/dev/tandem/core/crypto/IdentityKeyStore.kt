package dev.tandem.core.crypto

import java.security.PrivateKey
import java.security.PublicKey

/**
 * Testability seam for the phone identity key (E10-15): a non-exportable P-256 signing key used
 * for the TLS client certificate and its `CertificateVerify`. The production implementation
 * (`AndroidKeyStoreIdentityKeyStore`, E10-01) is backed by `AndroidKeyStore`; JVM `unit:` and
 * `integration:` tests use `SoftwareIdentityKeyStore` from this module's `testFixtures` source
 * set instead, since the real Keystore is unreachable off-device.
 */
interface IdentityKeyStore {
    /** Returns the existing key for [alias], generating a P-256 key pair if none exists yet. */
    fun getOrCreate(
        alias: String,
        preferStrongBox: Boolean,
    ): KeyHandle

    /** Returns the existing key for [alias], or null if it has not been generated. */
    fun get(alias: String): KeyHandle?

    /** Removes the key for [alias], if any. */
    fun delete(alias: String)
}

/**
 * A single identity key. [privateKey] is the handle JSSE signs with directly
 * (`X509ExtendedKeyManager.getPrivateKey()`, E12-06): it must work with both `SHA256withECDSA`
 * (certificate signing, E10-02) and `NONEwithECDSA` (TLS 1.3 `CertificateVerify` signs a
 * pre-computed transcript hash, not raw bytes — see docs/spikes/android-sslsocket-keystore.md).
 */
data class KeyHandle(
    val alias: String,
    val publicKey: PublicKey,
    val privateKey: PrivateKey,
    val securityLevel: SecurityLevel,
    val isHardwareBacked: Boolean,
)

/** Where the private key material is held. Real hardware properties are asserted only against the real impl. */
enum class SecurityLevel {
    SOFTWARE,
    TRUSTED_ENVIRONMENT,
    STRONGBOX,
}

sealed class IdentityKeyStoreException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/** Mirrors `android.security.keystore.StrongBoxUnavailableException` (E10-01's fallback trigger). */
class StrongBoxUnavailableException(
    cause: Throwable? = null,
) : IdentityKeyStoreException("StrongBox requested but unavailable", cause)

/** Mirrors a corrupted/unreadable Keystore alias (E10-04's recovery trigger). */
class KeystoreCorruptedException : IdentityKeyStoreException("Keystore is corrupted or unreadable")
