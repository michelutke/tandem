package dev.tandem.core.crypto

import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.ConcurrentHashMap

/** Which exception `failNextGenerate` arms on the next [SoftwareIdentityKeyStore.getOrCreate] call. */
enum class InjectedKeyStoreFailure {
    STRONGBOX_UNAVAILABLE,
    KEYSTORE_CORRUPTED,
}

/**
 * In-memory JCA P-256 fake of [IdentityKeyStore] for JVM `unit:`/`integration:` tests (E10-15):
 * `core/crypto`'s own AndroidKeyStore-fallback logic (E10-01), certificate generation (E10-02),
 * the TLS `X509KeyManager` (E12-06), pairing proof (E14-06) and the E15-15 JVM harness all run
 * against this instead of the real Keystore. Test-only: this class lives in `testFixtures` and
 * must never appear on a release classpath (see `tools/lint/test/release_apk_software_identity_key_store_absent_test.sh`).
 */
class SoftwareIdentityKeyStore : IdentityKeyStore {
    private val keys = ConcurrentHashMap<String, KeyHandle>()
    private var nextFailure: InjectedKeyStoreFailure? = null

    /** Makes the next [getOrCreate] call that actually generates a key throw instead. One-shot. */
    fun failNextGenerate(failure: InjectedKeyStoreFailure) {
        nextFailure = failure
    }

    override fun getOrCreate(
        alias: String,
        preferStrongBox: Boolean,
    ): KeyHandle {
        keys[alias]?.let { return it }

        nextFailure?.let { failure ->
            nextFailure = null
            throw when (failure) {
                InjectedKeyStoreFailure.STRONGBOX_UNAVAILABLE -> StrongBoxUnavailableException()
                InjectedKeyStoreFailure.KEYSTORE_CORRUPTED -> KeystoreCorruptedException()
            }
        }

        val keyPair =
            KeyPairGenerator
                .getInstance("EC")
                .apply { initialize(ECGenParameterSpec("secp256r1")) }
                .generateKeyPair()

        val handle =
            KeyHandle(
                alias = alias,
                publicKey = keyPair.public,
                privateKey = keyPair.private,
                securityLevel = SecurityLevel.SOFTWARE,
                isHardwareBacked = false,
            )
        keys[alias] = handle
        return handle
    }

    override fun get(alias: String): KeyHandle? = keys[alias]

    override fun delete(alias: String) {
        keys.remove(alias)
    }
}
