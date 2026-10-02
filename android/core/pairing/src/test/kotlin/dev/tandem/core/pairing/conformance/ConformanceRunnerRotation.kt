package dev.tandem.core.pairing.conformance

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.KeyRotation
import dev.tandem.protocol.v1.RotationAck
import dev.tandem.protocol.v1.RotationChallenge
import dev.tandem.protocol.v1.RotationReject
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayOutputStream
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

// E70-01: rotation-encoding conformance vector handlers, split out of ConformanceRunner.kt for the
// same LargeClass detekt budget reason as ConformanceRunnerMedia.kt (mirrors the macOS codec's own
// ConformanceRunner+Rotation.swift split).

private const val ROTATION_CATEGORY = "rotation-encoding"
private const val ROTATION_CHALLENGE_LENGTH = 32
private const val P256_SPKI_LENGTH = 91
private const val P256_SPKI_POINT_OFFSET = 26
private const val UNCOMPRESSED_POINT_TAG = 0x04
private val P256_SPKI_HEADER = hexToBytes("3059301306072a8648ce3d020106082a8648ce3d030107034200")
private val ROTATE_LABEL = "tandem-rotate-v1".toByteArray(Charsets.US_ASCII)

/** `rotation-encoding` category (E70-01): decodes the raw message bytes each vector describes
 * (`input.messageHex` -- see protocol/vectors/README.md) with the real generated rotation message
 * types (`protocol/proto/tandem/v1/rotation.proto`), selected by `input.kind`; `keyRotation` vectors
 * additionally verify both ECDSA signatures over the SPEC #key-rotation transcript. */
internal fun rotationEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    return try {
        when (val kind = input.getValue("kind").jsonPrimitive.content) {
            "rotationChallenge" -> {
                rotationChallengeOutcome(id, messageBytes, vector)
            }

            "rotationAck" -> {
                rotationRoundTripOutcome(id, messageBytes, vector, RotationAck.parseFrom(messageBytes).toByteArray())
            }

            "rotationReject" -> {
                rotationRejectOutcome(id, messageBytes, vector)
            }

            "keyRotation" -> {
                keyRotationOutcome(id, messageBytes, input, vector)
            }

            else -> {
                error("unsupported rotation-encoding kind: $kind")
            }
        }
    } catch (e: com.google.protobuf.InvalidProtocolBufferException) {
        VectorOutcome(id, ROTATION_CATEGORY, "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun rotationRoundTripOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
    reencoded: ByteArray,
): VectorOutcome {
    val expectedSha =
        vector
            .getValue("expected")
            .jsonObject
            .getValue("messageSha256")
            .jsonPrimitive.content
    val passed = reencoded.contentEquals(messageBytes) && sha256Hex(messageBytes) == expectedSha
    return VectorOutcome(
        id,
        ROTATION_CATEGORY,
        if (passed) "pass" else "fail",
        "sha256=$expectedSha",
        "sha256=${sha256Hex(messageBytes)}",
    )
}

private fun rotationChallengeOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded = RotationChallenge.parseFrom(messageBytes)
    val expectedChallenge =
        hexToBytes(
            vector
                .getValue("expected")
                .jsonObject
                .getValue("challengeHex")
                .jsonPrimitive.content,
        )
    val roundTrip = rotationRoundTripOutcome(id, messageBytes, vector, decoded.toByteArray())
    val passed =
        roundTrip.outcome == "pass" &&
            decoded.challenge.size() == ROTATION_CHALLENGE_LENGTH &&
            decoded.challenge == ByteString.copyFrom(expectedChallenge)
    return VectorOutcome(
        id,
        ROTATION_CATEGORY,
        if (passed) "pass" else "fail",
        "challengeLength=${expectedChallenge.size}",
        "challengeLength=${decoded.challenge.size()}",
    )
}

private fun rotationRejectOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded = RotationReject.parseFrom(messageBytes)
    val expectedReason =
        vector
            .getValue("expected")
            .jsonObject
            .getValue("reason")
            .jsonPrimitive.content
    val actualReason = decoded.reason.name.removePrefix("ROTATION_REJECT_REASON_")
    val roundTrip = rotationRoundTripOutcome(id, messageBytes, vector, decoded.toByteArray())
    val passed = roundTrip.outcome == "pass" && actualReason == expectedReason
    return VectorOutcome(
        id,
        ROTATION_CATEGORY,
        if (passed) "pass" else "fail",
        "reason=$expectedReason",
        "reason=$actualReason",
    )
}

private fun keyRotationOutcome(
    id: String,
    messageBytes: ByteArray,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val decoded = KeyRotation.parseFrom(messageBytes)
    val oldSpkiDer = hexToBytes(input.getValue("oldSpkiDerHex").jsonPrimitive.content)
    val cb = hexToBytes(input.getValue("cbHex").jsonPrimitive.content)
    val newSpkiDer = decoded.newSpkiDer.toByteArray()
    val transcript = rotationTranscript(oldSpkiDer, newSpkiDer, cb)
    val verified =
        isStrictP256Spki(newSpkiDer) &&
            verifyEcdsa(oldSpkiDer, transcript, decoded.sigOldKey.toByteArray()) &&
            verifyEcdsa(newSpkiDer, transcript, decoded.sigNewKey.toByteArray())
    if ("expected" in vector) {
        val roundTrip = rotationRoundTripOutcome(id, messageBytes, vector, decoded.toByteArray())
        val passed = verified && roundTrip.outcome == "pass"
        return VectorOutcome(id, ROTATION_CATEGORY, if (passed) "pass" else "fail", "valid=true", "valid=$verified")
    }
    val expectedError = vector.getValue("expectedError").jsonPrimitive.content
    val actual = if (verified) "valid" else "invalidSignature"
    return VectorOutcome(id, ROTATION_CATEGORY, if (actual == expectedError) "pass" else "fail", expectedError, actual)
}

private fun isStrictP256Spki(spkiDer: ByteArray): Boolean =
    spkiDer.size == P256_SPKI_LENGTH &&
        spkiDer.copyOfRange(0, P256_SPKI_POINT_OFFSET).contentEquals(P256_SPKI_HEADER) &&
        spkiDer[P256_SPKI_POINT_OFFSET].toInt() == UNCOMPRESSED_POINT_TAG

private fun rotationTranscript(
    oldSpkiDer: ByteArray,
    newSpkiDer: ByteArray,
    cb: ByteArray,
): ByteArray {
    val out = ByteArrayOutputStream()
    out.write(ROTATE_LABEL)
    for (part in listOf(oldSpkiDer, newSpkiDer, cb)) {
        out.write(part.size shr 8)
        out.write(part.size and 0xFF)
        out.write(part)
    }
    return out.toByteArray()
}

@Suppress("SwallowedException")
private fun verifyEcdsa(
    spkiDer: ByteArray,
    message: ByteArray,
    signatureDer: ByteArray,
): Boolean =
    try {
        val publicKey = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(spkiDer))
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(publicKey)
            update(message)
            verify(signatureDer)
        }
    } catch (e: GeneralSecurityException) {
        false
    }
