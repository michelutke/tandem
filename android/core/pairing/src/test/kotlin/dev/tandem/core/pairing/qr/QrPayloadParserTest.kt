package dev.tandem.core.pairing.qr

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

private const val VALID_FP = "bIeynz76iy05sAK-bVNEV5vcrEO5uQuuYQq6FJhTzUI"
private const val VALID_SECRET = "s1M4FPXbKtRZFFn8dntlVw" // gitleaks:allow (fixed test fixture, not a real secret)

/**
 * QrPayloadParser tests (E14-03). Vectors come from the committed E01-21 manifest
 * `protocol/vectors/qr-payload.json` (path wired via the `tandem.vectorsDir` system property,
 * android/core/pairing/build.gradle.kts) — same loading approach as DisplayStringSanitizerTest
 * (E14-21) uses for its own committed manifest.
 */
class QrPayloadParserTest {
    @Test
    fun parseInvite_eachValidQrVector_producesExpectedInvite() {
        val validVectors = loadVectors().filter { "expected" in it }
        assertTrue(validVectors.isNotEmpty(), "expected at least one valid qr-payload vector")

        for (vector in validVectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val uri =
                vector
                    .getValue("input")
                    .jsonObject
                    .getValue("uri")
                    .jsonPrimitive.content
            val expected = vector.getValue("expected").jsonObject

            val result = QrPayloadParser.parse(uri)

            val accepted = result as? ParseInviteResult.Accepted ?: error("expected Accepted for $id, got $result")
            val invite = accepted.invite
            assertEquals(
                expected.getValue("fingerprintHex").jsonPrimitive.content,
                invite.fingerprint.toHexString(),
                id,
            )
            assertEquals(expected.getValue("secretHex").jsonPrimitive.content, invite.secret.toHexString(), id)
            assertEquals(
                expected.getValue("addresses").jsonArray.map { it.jsonPrimitive.content },
                invite.addresses,
                id,
            )
            assertEquals(
                expected
                    .getValue("port")
                    .jsonPrimitive.content
                    .toInt(),
                invite.port,
                id,
            )
            assertEquals(
                hexToBytes(expected.getValue("nameHex").jsonPrimitive.content).toString(Charsets.UTF_8),
                invite.macName,
                id,
            )
        }
    }

    @Test
    fun parseInvite_eachMalformedQrVector_rejectedNoPartialInvite() {
        val malformedVectors = loadVectors().filter { "expectedError" in it }
        assertTrue(malformedVectors.isNotEmpty(), "expected at least one malformed qr-payload vector")

        for (vector in malformedVectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val uri =
                vector
                    .getValue("input")
                    .jsonObject
                    .getValue("uri")
                    .jsonPrimitive.content

            val result = QrPayloadParser.parse(uri)

            val rejected = result as? ParseInviteResult.Rejected ?: error("expected Rejected for $id, got $result")
            assertEquals(vector.getValue("expectedError").jsonPrimitive.content, rejected.error.wireName(), id)
            vector.getValue("input").jsonObject["invalidField"]?.jsonPrimitive?.content?.let { invalidField ->
                assertEquals(invalidField, rejected.error.field, id)
            }
        }
    }

    @Test
    fun parseInvite_versionTwo_rejectedUnsupportedVersion() {
        val uri = findVector("qr-payload-unsupported-version").uri()

        val result = QrPayloadParser.parse(uri)

        assertEquals(ParseInviteResult.Rejected(InviteError.UnsupportedVersion), result)
    }

    @Test
    fun parseInvite_missingFpOrSecret_rejectedMissingParam() {
        val missingFp = "tandem://pair?v=1&s=$VALID_SECRET&a=192.168.1.10&p=54321&n=Mac"
        val missingSecret = findVector("qr-payload-missing-field").uri()

        assertEquals(
            ParseInviteResult.Rejected(InviteError.MissingRequiredField("fp")),
            QrPayloadParser.parse(missingFp),
        )
        assertEquals(
            ParseInviteResult.Rejected(InviteError.MissingRequiredField("s")),
            QrPayloadParser.parse(missingSecret),
        )
    }

    @Test
    fun parseInvite_fpNot32Bytes_rejectedBadFingerprint() {
        val uri = findVector("qr-payload-fingerprint-wrong-length").uri()

        val result = QrPayloadParser.parse(uri)

        assertEquals(ParseInviteResult.Rejected(InviteError.InvalidFingerprint), result)
    }

    @Test
    fun parseInvite_hostnameOrMulticastAddress_rejectedInvalidAddress() {
        val hostnameUri = findVector("qr-payload-hostname-in-address-list").uri()
        val multicastUri = findVector("qr-payload-multicast-address").uri()

        assertEquals(ParseInviteResult.Rejected(InviteError.InvalidAddress), QrPayloadParser.parse(hostnameUri))
        assertEquals(ParseInviteResult.Rejected(InviteError.InvalidAddress), QrPayloadParser.parse(multicastUri))
    }

    @Test
    fun parseInvite_uncompressedEightGroupIpv6Address_accepted() {
        // Regression: no "::" compression, all 8 groups spelled out (RFC 3986 IPv6address's plain
        // "6( h16 ':' ) ls32" form, unrelated to any of the committed vectors, which are all
        // compressed).
        val address = "2001:db8:0:0:0:0:0:1"
        val uri = "tandem://pair?v=1&fp=$VALID_FP&s=$VALID_SECRET&a=$address&p=54321&n=Mac"

        val result = QrPayloadParser.parse(uri)

        val accepted = result as? ParseInviteResult.Accepted ?: error("expected Accepted, got $result")
        assertEquals(listOf(address), accepted.invite.addresses)
    }

    @Test
    fun parseInvite_macNameWithBidiOverride_sanitizedBeforeDisplay() {
        // U+202E RIGHT-TO-LEFT OVERRIDE (UTF-8 E2 80 AE) percent-encoded ahead of "Mac".
        val uri = "tandem://pair?v=1&fp=$VALID_FP&s=$VALID_SECRET&a=192.168.1.10&p=54321&n=%E2%80%AEMac"

        val result = QrPayloadParser.parse(uri)

        val accepted = result as? ParseInviteResult.Accepted ?: error("expected Accepted, got $result")
        assertEquals("Mac", accepted.invite.macName)
    }

    private companion object {
        fun loadVectors(): List<JsonObject> {
            val vectorsDir =
                System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
            val file = File(vectorsDir, "qr-payload.json")
            return Json
                .parseToJsonElement(file.readText())
                .jsonObject
                .getValue("vectors")
                .jsonArray
                .map { it.jsonObject }
        }

        fun findVector(id: String): JsonObject = loadVectors().first { it.getValue("id").jsonPrimitive.content == id }

        fun JsonObject.uri(): String =
            getValue("input")
                .jsonObject
                .getValue("uri")
                .jsonPrimitive.content

        fun hexToBytes(hex: String): ByteArray =
            ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

        fun ByteArray.toHexString(): String = joinToString("") { "%02x".format(it) }

        fun InviteError.wireName(): String = this::class.simpleName!!.replaceFirstChar { it.lowercase() }
    }
}
