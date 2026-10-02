package dev.tandem.core.pairing.conformance

import dev.tandem.protocol.v1.CallActionResult
import dev.tandem.protocol.v1.CallEvent
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E52-01: calls-encoding conformance vector handlers, split out of ConformanceRunner.kt for the same
// LargeClass detekt budget reason as ConformanceRunnerSms.kt (mirrors the macOS codec's own
// ConformanceRunner+Calls.swift split).

/** `calls-encoding` category (E52-01): decodes the raw message bytes each vector describes
 * (`input.messageHex` / `input.messageHexes` -- see protocol/vectors/README.md) with the real generated
 * CALLS message types (`protocol/proto/tandem/v1/calls.proto`), selected by `input.kind`. */
internal fun callsEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    return when (val kind = input.getValue("kind").jsonPrimitive.content) {
        "callEvent" -> {
            callEventOutcome(id, hexToBytes(input.getValue("messageHex").jsonPrimitive.content), vector)
        }

        "callStateSequence" -> {
            callStateSequenceOutcome(id, input, vector)
        }

        "callActionResult" -> {
            callActionResultOutcome(id, hexToBytes(input.getValue("messageHex").jsonPrimitive.content), vector)
        }

        else -> {
            error("unsupported calls-encoding kind: $kind")
        }
    }
}

private fun undecodable(
    id: String,
    e: Exception,
) = VectorOutcome(id, "calls-encoding", "fail", "decodable", "failed to decode: ${e::class.simpleName}")

private fun callEventOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            CallEvent.parseFrom(messageBytes)
        } catch (e: Exception) {
            return undecodable(id, e)
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedCallId = expected.getValue("callId").jsonPrimitive.content
    val expectedState = expected.getValue("state").jsonPrimitive.content
    val expectedTimestampMs =
        expected
            .getValue("timestampMs")
            .jsonPrimitive.content
            .toLong()
    val passed =
        decoded.callId == expectedCallId &&
            decoded.direction.name == expected.getValue("direction").jsonPrimitive.content &&
            decoded.state.name == expectedState &&
            decoded.address == expected.getValue("address").jsonPrimitive.content &&
            decoded.normalizedE164 == expected.getValue("normalizedE164").jsonPrimitive.content &&
            decoded.timestampMs == expectedTimestampMs &&
            decoded.toByteArray().contentEquals(messageBytes) &&
            sha256Hex(messageBytes) == expected.getValue("messageSha256").jsonPrimitive.content
    return VectorOutcome(
        id,
        "calls-encoding",
        if (passed) "pass" else "fail",
        "callId=$expectedCallId state=$expectedState",
        "callId=${decoded.callId} state=${decoded.state.name}",
    )
}

private fun callStateSequenceOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            input.getValue("messageHexes").jsonArray.map {
                CallEvent.parseFrom(hexToBytes(it.jsonPrimitive.content))
            }
        } catch (e: Exception) {
            return undecodable(id, e)
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedCallId = expected.getValue("callId").jsonPrimitive.content
    val expectedStates = expected.getValue("states").jsonArray.map { it.jsonPrimitive.content }
    val expectedTimestampsMs =
        expected.getValue("timestampsMs").jsonArray.map { it.jsonPrimitive.content.toLong() }
    val actualStates = decoded.map { it.state.name }
    val passed =
        decoded.all { it.callId == expectedCallId } &&
            actualStates == expectedStates &&
            decoded.map { it.timestampMs } == expectedTimestampsMs
    return VectorOutcome(
        id,
        "calls-encoding",
        if (passed) "pass" else "fail",
        "callId=$expectedCallId states=$expectedStates",
        "callIds=${decoded.map { it.callId }.distinct()} states=$actualStates",
    )
}

private fun callActionResultOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            CallActionResult.parseFrom(messageBytes)
        } catch (e: Exception) {
            return undecodable(id, e)
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedRequestId = expected.getValue("requestId").jsonPrimitive.content
    val expectedErrorCode = expected.getValue("errorCode").jsonPrimitive.content
    val expectedSuccess =
        expected
            .getValue("success")
            .jsonPrimitive.content
            .toBoolean()
    val passed =
        decoded.requestId == expectedRequestId &&
            decoded.callId == expected.getValue("callId").jsonPrimitive.content &&
            decoded.success == expectedSuccess &&
            decoded.errorCode.name == expectedErrorCode
    return VectorOutcome(
        id,
        "calls-encoding",
        if (passed) "pass" else "fail",
        "requestId=$expectedRequestId success=$expectedSuccess errorCode=$expectedErrorCode",
        "requestId=${decoded.requestId} success=${decoded.success} errorCode=${decoded.errorCode.name}",
    )
}
