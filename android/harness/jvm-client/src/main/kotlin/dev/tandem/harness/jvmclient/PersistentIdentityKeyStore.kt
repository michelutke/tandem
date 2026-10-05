package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.IdentityKeyStore
import dev.tandem.core.crypto.KeyHandle
import dev.tandem.core.crypto.SecurityLevel
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.security.KeyFactory
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.time.Clock

/**
 * [IdentityKeyStore] for the JVM harness client (E15-21): the harness's phone identity is
 * generated the same way any JVM test's is (delegates key generation to [SoftwareIdentityKeyStore],
 * E10-15), but is additionally serialized to [file] so a restarted harness process loads the same
 * key instead of generating a fresh one — the real `AndroidKeyStoreIdentityKeyStore` gets this for
 * free from `AndroidKeyStore` itself; a JVM fake has no such persistent store to fall back on.
 * [file] holds the PKCS#8-encoded private key and the self-signed certificate's DER, length-prefixed;
 * the public key is never stored separately since it is recoverable from the certificate.
 */
class PersistentIdentityKeyStore(
    clock: Clock,
    private val file: File,
) : IdentityKeyStore {
    private val delegate = SoftwareIdentityKeyStore(clock)
    private var cached: KeyHandle? = null

    override fun getOrCreate(
        alias: String,
        preferStrongBox: Boolean,
    ): KeyHandle {
        cached?.let { return it }
        val handle = if (file.exists()) readFrom(file, alias) else generateAndPersist(alias, preferStrongBox)
        cached = handle
        return handle
    }

    override fun get(alias: String): KeyHandle? =
        cached ?: if (file.exists()) getOrCreate(alias, preferStrongBox = false) else null

    override fun delete(alias: String) {
        cached = null
        delegate.delete(alias)
        file.delete()
    }

    private fun generateAndPersist(
        alias: String,
        preferStrongBox: Boolean,
    ): KeyHandle {
        val handle = delegate.getOrCreate(alias, preferStrongBox)
        write(file, handle)
        return handle
    }

    private fun readFrom(
        file: File,
        alias: String,
    ): KeyHandle =
        DataInputStream(file.inputStream()).use { input ->
            val privateKeyBytes = ByteArray(input.readInt()).also { input.readFully(it) }
            val certificateBytes = ByteArray(input.readInt()).also { input.readFully(it) }

            val privateKey = KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(privateKeyBytes))
            val certificateFactory = CertificateFactory.getInstance("X.509")
            val certificate = certificateFactory.generateCertificate(certificateBytes.inputStream()) as X509Certificate

            KeyHandle(
                alias = alias,
                publicKey = certificate.publicKey,
                privateKey = privateKey,
                securityLevel = SecurityLevel.SOFTWARE,
                isHardwareBacked = false,
                certificate = certificate,
            )
        }

    companion object {
        const val IDENTITY_ALIAS = "harness-jvm-client"

        /** Writes [handle] to [file] in the format a [PersistentIdentityKeyStore] reads back as its identity. */
        fun write(
            file: File,
            handle: KeyHandle,
        ) {
            file.parentFile?.mkdirs()
            DataOutputStream(file.outputStream()).use { out ->
                val privateKeyBytes = handle.privateKey.encoded
                val certificateBytes = handle.certificate.encoded
                out.writeInt(privateKeyBytes.size)
                out.write(privateKeyBytes)
                out.writeInt(certificateBytes.size)
                out.write(certificateBytes)
            }
        }
    }
}
