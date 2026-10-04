package dev.tandem.core.pairing.conformance

import com.google.protobuf.InvalidProtocolBufferException
import dev.tandem.protocol.v1.Commitment
import dev.tandem.protocol.v1.ManualPairResult
import dev.tandem.protocol.v1.Reveal
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigInteger
import java.security.MessageDigest

// E73-02: manual-pairing conformance vector handlers, split out of ConformanceRunner.kt for the same
// LargeClass detekt budget reason as ConformanceRunnerInput.kt (mirrors the macOS codec's own
// ConformanceRunner+ManualPairing.swift split).

private const val CATEGORY = "manual-pairing"
private const val HASH_LENGTH = 32
private const val NONCE_LENGTH = 16
private const val SAS_MODULUS = 1_000_000L
private const val SAS_HMAC_PREFIX_BYTES = 8
private const val HMAC_BLOCK_BYTES = 64
private const val PAIR_LABEL = "tandem-manual-pair-v1"
private const val COMMIT_LABEL = "tandem-manual-commit-v1"
private val ROLE_BYTES = mapOf("phone" to 0x01.toByte(), "mac" to 0x02.toByte())
private val VALID_SEQUENCE =
    listOf(
        "phone" to "commitment",
        "mac" to "commitment",
        "phone" to "reveal",
        "mac" to "reveal",
        "mac" to "manualPairResult",
    )

private class SasInputs(
    val noncePhone: ByteArray,
    val nonceMac: ByteArray,
    val macSpki: ByteArray,
    val phoneSpki: ByteArray,
    val cb: ByteArray,
)

/** `manual-pairing` category (E73-02): dispatches on `input.kind` (`message`, `sas`, `commitment`,
 * `sasCompare`, `sequence`) and compares the result with `expectedError` or `expected`; see
 * protocol/vectors/README.md. */
internal fun manualPairingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    return try {
        when (input.getValue("kind").jsonPrimitive.content) {
            "message" -> manualMessageOutcome(id, vector, input)
            "sas" -> manualSasOutcome(id, vector, input)
            "commitment" -> manualVerdictOutcome(id, vector, commitmentVerdict(input))
            "sasCompare" -> manualSasCompareOutcome(id, vector, input)
            "sequence" -> manualVerdictOutcome(id, vector, sequenceVerdict(input.getValue("messages").jsonArray))
            else -> VectorOutcome(id, CATEGORY, "fail", "known kind", "unknown kind")
        }
    } catch (e: InvalidProtocolBufferException) {
        VectorOutcome(id, CATEGORY, "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun manualVerdictOutcome(
    id: String,
    vector: JsonObject,
    verdict: String,
): VectorOutcome {
    val expected = if ("expectedError" in vector) vector.getValue("expectedError").jsonPrimitive.content else "accepted"
    return VectorOutcome(id, CATEGORY, if (verdict == expected) "pass" else "fail", expected, verdict)
}

private fun manualMessageOutcome(
    id: String,
    vector: JsonObject,
    input: JsonObject,
): VectorOutcome {
    val type = input.getValue("messageType").jsonPrimitive.content
    val bytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val (verdict, summary, reencoded) = decodeManualMessage(type, bytes)
    if ("expectedError" in vector) return manualVerdictOutcome(id, vector, verdict)
    val expected = vector.getValue("expected").jsonObject
    val expectedSummary = expected.getValue("summary").jsonPrimitive.content
    val passed =
        verdict == "accepted" &&
            summary == expectedSummary &&
            reencoded.contentEquals(bytes) &&
            sha256Hex(bytes) == expected.getValue("messageSha256").jsonPrimitive.content
    return VectorOutcome(id, CATEGORY, if (passed) "pass" else "fail", expectedSummary, summary)
}

private fun decodeManualMessage(
    type: String,
    bytes: ByteArray,
): Triple<String, String, ByteArray> =
    when (type) {
        "commitment" -> {
            val message = Commitment.parseFrom(bytes)
            val verdict = if (message.hash.size() == HASH_LENGTH) "accepted" else "malformedCommitment"
            Triple(verdict, "type=commitment|hash=${message.hash.toByteArray().toHex()}", message.toByteArray())
        }

        "reveal" -> {
            val message = Reveal.parseFrom(bytes)
            val verdict = if (message.nonce.size() == NONCE_LENGTH) "accepted" else "malformedReveal"
            Triple(verdict, "type=reveal|nonce=${message.nonce.toByteArray().toHex()}", message.toByteArray())
        }

        else -> {
            val message = ManualPairResult.parseFrom(bytes)
            val verdict = if (message.accepted) "accepted" else "resultNotAccepted"
            Triple(verdict, "type=manualPairResult|accepted=${message.accepted}", message.toByteArray())
        }
    }

private fun manualSasOutcome(
    id: String,
    vector: JsonObject,
    input: JsonObject,
): VectorOutcome {
    val inputs = sasInputs(input)
    val expected = vector.getValue("expected").jsonObject
    val actual =
        mapOf(
            "commitPhoneHex" to commit("phone", inputs.noncePhone, inputs).toHex(),
            "commitMacHex" to commit("mac", inputs.nonceMac, inputs).toHex(),
            "hmacHex" to sasHmac(inputs).toHex(),
            "sas" to sas(inputs),
        )
    val passed = actual.all { (key, value) -> expected.getValue(key).jsonPrimitive.content == value }
    return VectorOutcome(
        id,
        CATEGORY,
        if (passed) "pass" else "fail",
        expected.getValue("sas").jsonPrimitive.content,
        actual.getValue("sas"),
    )
}

private fun manualSasCompareOutcome(
    id: String,
    vector: JsonObject,
    input: JsonObject,
): VectorOutcome {
    val phoneSas = sas(sasInputs(input.getValue("phoneView").jsonObject))
    val macSas = sas(sasInputs(input.getValue("macView").jsonObject))
    val verdict = if (phoneSas == macSas) "accepted" else "sasMismatch"
    val outcome = manualVerdictOutcome(id, vector, verdict)
    if (outcome.outcome != "pass" || "expectedError" in vector) return outcome
    val expectedSas =
        vector
            .getValue("expected")
            .jsonObject
            .getValue("sas")
            .jsonPrimitive.content
    return outcome.copy(
        outcome =
            if (expectedSas ==
                phoneSas
            ) {
                "pass"
            } else {
                "fail"
            },
        expected = expectedSas,
        actual = phoneSas,
    )
}

private fun commitmentVerdict(input: JsonObject): String {
    val inputs =
        SasInputs(
            noncePhone = ByteArray(0),
            nonceMac = ByteArray(0),
            macSpki = hexToBytes(input.getValue("macSpkiDerHex").jsonPrimitive.content),
            phoneSpki = hexToBytes(input.getValue("phoneSpkiDerHex").jsonPrimitive.content),
            cb = hexToBytes(input.getValue("cbHex").jsonPrimitive.content),
        )
    val role = input.getValue("committerRole").jsonPrimitive.content
    val recomputed = commit(role, hexToBytes(input.getValue("revealNonceHex").jsonPrimitive.content), inputs)
    val received = hexToBytes(input.getValue("commitmentHex").jsonPrimitive.content)
    return if (MessageDigest.isEqual(recomputed, received)) "accepted" else "commitmentMismatch"
}

private fun sequenceVerdict(messages: JsonArray): String {
    val observed =
        messages.map {
            val message = it.jsonObject
            message.getValue("from").jsonPrimitive.content to message.getValue("type").jsonPrimitive.content
        }
    val inOrder = observed.size <= VALID_SEQUENCE.size && observed == VALID_SEQUENCE.take(observed.size)
    return if (inOrder &&
        observed.size == VALID_SEQUENCE.size
    ) {
        "accepted"
    } else if (inOrder) {
        "incomplete"
    } else {
        "outOfOrder"
    }
}

private fun sasInputs(view: JsonObject): SasInputs =
    SasInputs(
        noncePhone = hexToBytes(view.getValue("noncePhoneHex").jsonPrimitive.content),
        nonceMac = hexToBytes(view.getValue("nonceMacHex").jsonPrimitive.content),
        macSpki = hexToBytes(view.getValue("macSpkiDerHex").jsonPrimitive.content),
        phoneSpki = hexToBytes(view.getValue("phoneSpkiDerHex").jsonPrimitive.content),
        cb = hexToBytes(view.getValue("cbHex").jsonPrimitive.content),
    )

private fun lengthPrefixed(bytes: ByteArray): ByteArray =
    byteArrayOf((bytes.size shr 8).toByte(), bytes.size.toByte()) + bytes

private fun context(inputs: SasInputs): ByteArray =
    PAIR_LABEL.toByteArray(Charsets.US_ASCII) +
        lengthPrefixed(inputs.macSpki) +
        lengthPrefixed(inputs.phoneSpki) +
        lengthPrefixed(inputs.cb)

private fun commit(
    role: String,
    nonce: ByteArray,
    inputs: SasInputs,
): ByteArray =
    MessageDigest
        .getInstance("SHA-256")
        .digest(
            COMMIT_LABEL.toByteArray(Charsets.US_ASCII) + byteArrayOf(ROLE_BYTES.getValue(role)) + nonce +
                context(inputs),
        )

/** RFC 2104 over `MessageDigest` SHA-256: an independent reference for the vectors, since HMAC outside
 * core/crypto is banned by the `KeyMaterialOnlyInCrypto` detekt rule. */
private fun sasHmac(inputs: SasInputs): ByteArray {
    val key = inputs.noncePhone + inputs.nonceMac
    val paddedKey = key + ByteArray(HMAC_BLOCK_BYTES - key.size)
    val sha256 = MessageDigest.getInstance("SHA-256")
    val inner =
        sha256.digest(ByteArray(HMAC_BLOCK_BYTES) { (paddedKey[it].toInt() xor 0x36).toByte() } + sasMessage(inputs))
    return sha256.digest(ByteArray(HMAC_BLOCK_BYTES) { (paddedKey[it].toInt() xor 0x5c).toByte() } + inner)
}

private fun sasMessage(inputs: SasInputs): ByteArray = PAIR_LABEL.toByteArray(Charsets.US_ASCII) + context(inputs)

private fun sas(inputs: SasInputs): String {
    val prefix = BigInteger(1, sasHmac(inputs).copyOfRange(0, SAS_HMAC_PREFIX_BYTES))
    return prefix.mod(BigInteger.valueOf(SAS_MODULUS)).toString().padStart(6, '0')
}
