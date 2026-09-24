package com.tandem.spike.keystoresslsocket

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.Certificate
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import javax.security.auth.x500.X500Principal

private const val ANDROID_KEY_STORE = "AndroidKeyStore"

/**
 * Spike helper: generates (or loads) a non-exportable P-256 key in AndroidKeyStore, preferring
 * StrongBox and falling back to TEE. AndroidKeyStore attaches a self-signed certificate to the
 * key at generation time; that certificate chain is what the KeyManager presents on the wire.
 */
object KeystoreIdentity {

    data class Generated(
        val alias: String,
        val requestedStrongBox: Boolean,
        val strongBoxGranted: Boolean,
    )

    fun generateP256(alias: String, preferStrongBox: Boolean = true): Generated {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }

        fun build(strongBox: Boolean): KeyGenParameterSpec =
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                // Conscrypt signs the already-hashed 32-byte transcript hash directly
                // (NONEwithECDSA) for TLS 1.3 CertificateVerify, not SHA256withECDSA over the raw
                // transcript; DIGEST_NONE must be permitted or that Signature engine lookup fails
                // inside the TLS stack with no clear exception surfacing to app code.
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)
                .setCertificateSubject(X500Principal("CN=tandem-spike-e03-03"))
                .setCertificateSerialNumber(BigInteger.ONE)
                .setIsStrongBoxBacked(strongBox)
                .build()

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            ANDROID_KEY_STORE,
        )

        var strongBoxGranted = false
        if (preferStrongBox) {
            try {
                generator.initialize(build(strongBox = true))
                generator.generateKeyPair()
                strongBoxGranted = true
            } catch (e: StrongBoxUnavailableException) {
                strongBoxGranted = false
            }
        }
        if (!strongBoxGranted) {
            generator.initialize(build(strongBox = false))
            generator.generateKeyPair()
        }

        return Generated(
            alias = alias,
            requestedStrongBox = preferStrongBox,
            strongBoxGranted = strongBoxGranted,
        )
    }

    fun certificateChain(alias: String): Array<X509Certificate> {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        val chain: Array<Certificate> = keyStore.getCertificateChain(alias)
            ?: error("no certificate chain for alias $alias")
        return chain.map { it as X509Certificate }.toTypedArray()
    }

    fun privateKey(alias: String): PrivateKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        return keyStore.getKey(alias, null) as PrivateKey
    }

    /** Reports where the key actually lives, per KeyInfo — the source of truth, not marketing specs. */
    fun keyInfo(alias: String): KeyInfo {
        val privateKey = privateKey(alias)
        val factory = KeyFactory.getInstance(privateKey.algorithm, ANDROID_KEY_STORE)
        return factory.getKeySpec(privateKey, KeyInfo::class.java)
    }

    fun securityLevelName(keyInfo: KeyInfo): String {
        // KeyInfo.getSecurityLevel() was added in API 31; API 29/30 only expose the coarser
        // isInsideSecureHardware() boolean (StrongBox vs TEE isn't distinguishable there).
        if (android.os.Build.VERSION.SDK_INT < 31) {
            return if (keyInfo.isInsideSecureHardware) "SECURE_HARDWARE(TEE_OR_STRONGBOX, API<31)" else "SOFTWARE"
        }
        return when (keyInfo.securityLevel) {
            KeyProperties.SECURITY_LEVEL_STRONGBOX -> "STRONGBOX"
            KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "TRUSTED_ENVIRONMENT"
            KeyProperties.SECURITY_LEVEL_SOFTWARE -> "SOFTWARE"
            KeyProperties.SECURITY_LEVEL_UNKNOWN -> "UNKNOWN"
            KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> "UNKNOWN_SECURE"
            else -> "OTHER(${keyInfo.securityLevel})"
        }
    }

    fun delete(alias: String) {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }
    }
}
