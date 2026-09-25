package dev.tandem.core.crypto

import java.io.ByteArrayInputStream
import java.math.BigInteger
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Hand-rolled minimal X.509v3 DER encoder for [SoftwareIdentityKeyStore]'s self-signed identity
 * certificate (E10-02). The real `AndroidKeyStoreIdentityKeyStore` never needs this: AndroidKeyStore
 * builds and signs its own self-signed placeholder certificate on-device from
 * `KeyGenParameterSpec.setCertificateSubject`/etc. There is no JVM-side equivalent, and the backlog
 * explicitly prefers this hand-rolled encoder over adding BouncyCastle as a new dependency just for
 * JVM `unit:` tests. Encodes exactly the fields `IdentityCertSpec` fixes, plus a `basicConstraints
 * CA:false` / `keyUsage digitalSignature` extension pair (neither of which
 * `KeyGenParameterSpec`'s certificate setters can express, so the real device cert gets them from
 * AndroidKeyStore's own defaults for a `PURPOSE_SIGN` key), self-signed with `SHA256withECDSA`.
 * Test-only: lives in `testFixtures`, never on a release classpath.
 */
internal fun buildSelfSignedCertificate(
    publicKey: PublicKey,
    privateKey: PrivateKey,
    spec: IdentityCertSpec,
): X509Certificate {
    val signatureAlgorithm = Der.sequence(Der.oid(OID_ECDSA_WITH_SHA256))
    val name = spec.subject.encoded

    val tbsCertificate =
        Der.sequence(
            Der.explicitTag(0, Der.integer(BigInteger.valueOf(2))),
            Der.integer(spec.serialNumber),
            signatureAlgorithm,
            name,
            Der.sequence(Der.time(spec.notBefore), Der.time(spec.notAfter)),
            name,
            publicKey.encoded,
            Der.explicitTag(3, Der.sequence(basicConstraintsExtension(), keyUsageExtension())),
        )

    val signature =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(tbsCertificate)
            sign()
        }

    val certificateDer =
        Der.sequence(tbsCertificate, signatureAlgorithm, Der.bitString(signature, unusedBits = 0))

    return CertificateFactory
        .getInstance("X.509")
        .generateCertificate(ByteArrayInputStream(certificateDer)) as X509Certificate
}

private const val OID_ECDSA_WITH_SHA256 = "1.2.840.10045.4.3.2"
private const val OID_BASIC_CONSTRAINTS = "2.5.29.19"
private const val OID_KEY_USAGE = "2.5.29.15"
private const val KEY_USAGE_DIGITAL_SIGNATURE: Byte = 0x80.toByte()

private fun basicConstraintsExtension(): ByteArray =
    Der.sequence(Der.oid(OID_BASIC_CONSTRAINTS), Der.booleanValue(true), Der.octetString(Der.sequence()))

private fun keyUsageExtension(): ByteArray =
    Der.sequence(
        Der.oid(OID_KEY_USAGE),
        Der.booleanValue(true),
        Der.octetString(Der.bitString(byteArrayOf(KEY_USAGE_DIGITAL_SIGNATURE), unusedBits = 7)),
    )

/** Minimal DER (X.690) TLV encoder — only the constructs an X.509v3 self-signed leaf cert needs. */
private object Der {
    fun tlv(
        tag: Int,
        content: ByteArray,
    ): ByteArray = byteArrayOf(tag.toByte()) + length(content.size) + content

    private fun length(size: Int): ByteArray {
        if (size < 0x80) return byteArrayOf(size.toByte())
        var value = size
        val bytes = ArrayDeque<Byte>()
        while (value > 0) {
            bytes.addFirst((value and 0xFF).toByte())
            value = value ushr 8
        }
        return byteArrayOf((0x80 or bytes.size).toByte()) + bytes.toByteArray()
    }

    fun sequence(vararg parts: ByteArray): ByteArray = tlv(0x30, parts.fold(ByteArray(0)) { acc, part -> acc + part })

    fun integer(value: BigInteger): ByteArray = tlv(0x02, value.toByteArray())

    fun booleanValue(value: Boolean): ByteArray = tlv(0x01, byteArrayOf(if (value) 0xFF.toByte() else 0x00))

    fun octetString(content: ByteArray): ByteArray = tlv(0x04, content)

    fun bitString(
        content: ByteArray,
        unusedBits: Int,
    ): ByteArray = tlv(0x03, byteArrayOf(unusedBits.toByte()) + content)

    fun explicitTag(
        tagNumber: Int,
        content: ByteArray,
    ): ByteArray = tlv(0xA0 or tagNumber, content)

    fun oid(dotted: String): ByteArray {
        val components = dotted.split(".").map(String::toInt)
        val body = mutableListOf<Byte>()
        body += (components[0] * 40 + components[1]).toByte()
        components.drop(2).forEach { component -> body += base128(component) }
        return tlv(0x06, body.toByteArray())
    }

    private fun base128(value: Int): List<Byte> {
        val groups = ArrayDeque<Int>()
        groups.addFirst(value and 0x7F)
        var remaining = value ushr 7
        while (remaining > 0) {
            groups.addFirst((remaining and 0x7F) or 0x80)
            remaining = remaining ushr 7
        }
        return groups.map(Int::toByte)
    }

    fun time(instant: Instant): ByteArray {
        val year = instant.atZone(ZoneOffset.UTC).year
        return if (year in 1950..2049) utcTime(instant) else generalizedTime(instant)
    }

    private fun utcTime(instant: Instant): ByteArray {
        val text = DateTimeFormatter.ofPattern("yyMMddHHmmss").withZone(ZoneOffset.UTC).format(instant) + "Z"
        return tlv(0x17, text.toByteArray(Charsets.US_ASCII))
    }

    private fun generalizedTime(instant: Instant): ByteArray {
        val text = DateTimeFormatter.ofPattern("yyyyMMddHHmmss").withZone(ZoneOffset.UTC).format(instant) + "Z"
        return tlv(0x18, text.toByteArray(Charsets.US_ASCII))
    }
}
