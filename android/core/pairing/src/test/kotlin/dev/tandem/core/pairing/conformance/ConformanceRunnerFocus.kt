package dev.tandem.core.pairing.conformance

import dev.tandem.protocol.v1.FocusState
import dev.tandem.protocol.v1.FocusSyncCapability
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E72-04: focus-encoding conformance vector handlers, split out of ConformanceRunner.kt for the same
// LargeClass detekt budget reason as ConformanceRunnerMedia.kt (mirrors the macOS codec's own
// ConformanceRunner+Focus.swift split).

/** `focus-encoding` category (E72-04): decodes the raw message bytes each vector describes
 * (`input.messageHex` -- see protocol/vectors/README.md) with the real generated focus-sync message
 * types (`protocol/proto/tandem/v1/focus.proto`), selected by `input.kind`. */
internal fun focusEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val expected = vector.getValue("expected").jsonObject
    val expectedFlag = expected.getValue("flag").jsonPrimitive.boolean
    val expectedSha = expected.getValue("messageSha256").jsonPrimitive.content
    return try {
        val (actualFlag, reencoded) = decodeFocusMessage(input.getValue("kind").jsonPrimitive.content, messageBytes)
        val passed =
            actualFlag == expectedFlag &&
                reencoded.contentEquals(messageBytes) &&
                sha256Hex(messageBytes) == expectedSha
        VectorOutcome(id, "focus-encoding", if (passed) "pass" else "fail", "flag=$expectedFlag", "flag=$actualFlag")
    } catch (e: com.google.protobuf.InvalidProtocolBufferException) {
        VectorOutcome(id, "focus-encoding", "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun decodeFocusMessage(
    kind: String,
    messageBytes: ByteArray,
): Pair<Boolean, ByteArray> {
    if (kind == "focusState") {
        val decoded = FocusState.parseFrom(messageBytes)
        return decoded.on to decoded.toByteArray()
    }
    check(kind == "focusSyncCapability") { "unsupported focus-encoding kind: $kind" }
    val decoded = FocusSyncCapability.parseFrom(messageBytes)
    return decoded.available to decoded.toByteArray()
}
