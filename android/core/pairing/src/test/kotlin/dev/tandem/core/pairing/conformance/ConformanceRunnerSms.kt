package dev.tandem.core.pairing.conformance

import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.protocol.v1.SendSmsStatus
import dev.tandem.protocol.v1.SmsMessage
import dev.tandem.protocol.v1.SmsSyncResponse
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E50-01: sms-encoding conformance vector handlers, split out of ConformanceRunner.kt for the same
// LargeClass detekt budget reason as ConformanceRunnerPhotos.kt (mirrors the macOS codec's own
// ConformanceRunner+Sms.swift split).

/** `sms-encoding` category (E50-01): decodes the raw message bytes each vector describes
 * (`input.messageHex` -- see protocol/vectors/README.md) with the real generated SMS message types
 * (`protocol/proto/tandem/v1/sms.proto`), selected by `input.kind`; `smsEnvelopeFrame` instead runs the
 * frame's 4-byte length prefix through the real [FrameDecoder]. */
internal fun smsEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    return when (val kind = input.getValue("kind").jsonPrimitive.content) {
        "smsMessage" -> smsMessageOutcome(id, hexToBytes(input.messageHex()), vector)
        "sendSmsStatus" -> sendSmsStatusOutcome(id, hexToBytes(input.messageHex()), vector)
        "smsSyncResponse" -> smsSyncResponseOutcome(id, hexToBytes(input.messageHex()), vector)
        "smsEnvelopeFrame" -> smsEnvelopeFrameOutcome(id, input, vector)
        else -> error("unsupported sms-encoding kind: $kind")
    }
}

private fun JsonObject.messageHex(): String = getValue("messageHex").jsonPrimitive.content

private fun undecodable(
    id: String,
    e: Exception,
) = VectorOutcome(id, "sms-encoding", "fail", "decodable", "failed to decode: ${e::class.simpleName}")

private fun smsMessageOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            SmsMessage.parseFrom(messageBytes)
        } catch (e: Exception) {
            return undecodable(id, e)
        }
    val expected = vector.getValue("expected").jsonObject
    val passed =
        decoded.id ==
            expected
                .getValue("id")
                .jsonPrimitive.content
                .toLong() &&
            decoded.threadId ==
            expected
                .getValue("threadId")
                .jsonPrimitive.content
                .toLong() &&
            decoded.address == expected.getValue("address").jsonPrimitive.content &&
            decoded.body == expected.getValue("body").jsonPrimitive.content &&
            decoded.timestampMs ==
            expected
                .getValue("timestampMs")
                .jsonPrimitive.content
                .toLong() &&
            decoded.type.name == expected.getValue("type").jsonPrimitive.content &&
            decoded.subscriptionId ==
            expected
                .getValue("subscriptionId")
                .jsonPrimitive.content
                .toInt() &&
            decoded.deliveryStatus.name == expected.getValue("deliveryStatus").jsonPrimitive.content &&
            sha256Hex(messageBytes) == expected.getValue("messageSha256").jsonPrimitive.content
    val expectedId = expected.getValue("id").jsonPrimitive.content
    val expectedType = expected.getValue("type").jsonPrimitive.content
    return VectorOutcome(
        id,
        "sms-encoding",
        if (passed) "pass" else "fail",
        "id=$expectedId type=$expectedType",
        "id=${decoded.id} type=${decoded.type.name}",
    )
}

private fun sendSmsStatusOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            SendSmsStatus.parseFrom(messageBytes)
        } catch (e: Exception) {
            return undecodable(id, e)
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedClientMessageId = expected.getValue("clientMessageId").jsonPrimitive.content
    val expectedState = expected.getValue("state").jsonPrimitive.content
    val expectedErrorCode = expected.getValue("errorCode").jsonPrimitive.content
    val expectedProviderMessageId =
        expected
            .getValue("providerMessageId")
            .jsonPrimitive.content
            .toLong()
    val passed =
        decoded.clientMessageId == expectedClientMessageId &&
            decoded.state.name == expectedState &&
            decoded.errorCode.name == expectedErrorCode &&
            decoded.providerMessageId == expectedProviderMessageId
    return VectorOutcome(
        id,
        "sms-encoding",
        if (passed) "pass" else "fail",
        "clientMessageId=$expectedClientMessageId state=$expectedState errorCode=$expectedErrorCode",
        "clientMessageId=${decoded.clientMessageId} state=${decoded.state.name} errorCode=${decoded.errorCode.name}",
    )
}

private fun smsSyncResponseOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            SmsSyncResponse.parseFrom(messageBytes)
        } catch (e: Exception) {
            return undecodable(id, e)
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedStatus = expected.getValue("status").jsonPrimitive.content
    val expectedThreadCount =
        expected
            .getValue("threadCount")
            .jsonPrimitive.content
            .toInt()
    val expectedMessageIds = expected.getValue("messageIds").jsonArray.map { it.jsonPrimitive.content.toLong() }
    val expectedHighWatermarkId =
        expected
            .getValue("highWatermarkId")
            .jsonPrimitive.content
            .toLong()
    val expectedBackfillCursorId =
        expected
            .getValue("backfillCursorId")
            .jsonPrimitive.content
            .toLong()
    val expectedBackfillComplete =
        expected
            .getValue("backfillComplete")
            .jsonPrimitive.content
            .toBoolean()
    val actualMessageIds = decoded.messagesList.map { it.id }
    val passed =
        decoded.status.name == expectedStatus &&
            decoded.threadsCount == expectedThreadCount &&
            actualMessageIds == expectedMessageIds &&
            decoded.highWatermarkId == expectedHighWatermarkId &&
            decoded.backfillCursorId == expectedBackfillCursorId &&
            decoded.backfillComplete == expectedBackfillComplete
    return VectorOutcome(
        id,
        "sms-encoding",
        if (passed) "pass" else "fail",
        "status=$expectedStatus messageIds=$expectedMessageIds backfillCursorId=$expectedBackfillCursorId",
        "status=${decoded.status.name} messageIds=$actualMessageIds backfillCursorId=${decoded.backfillCursorId}",
    )
}

private fun smsEnvelopeFrameOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val frameBytes = hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
    val decoded = runBlocking { FrameDecoder.decodeFrame(sourceFor(frameBytes)) }
    val rejected = decoded as? DecodeResult.Rejected
    val expectedClose = vector.getValue("closeCode").jsonPrimitive.content
    val expectedReason = vector.getValue("localReason").jsonPrimitive.content
    val passed =
        rejected != null && rejected.closeCode.name == expectedClose && rejected.reason.name == expectedReason
    val actual = if (rejected != null) "${rejected.closeCode.name}:${rejected.reason.name}" else decoded.toString()
    return VectorOutcome(id, "sms-encoding", if (passed) "pass" else "fail", "$expectedClose:$expectedReason", actual)
}
