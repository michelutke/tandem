package dev.tandem.core.pairing.conformance

import dev.tandem.protocol.v1.OriginalRequest
import dev.tandem.protocol.v1.PhotoError
import dev.tandem.protocol.v1.PhotoPageResult
import dev.tandem.protocol.v1.ThumbResult
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E41-01: photos-encoding conformance vector handlers, split out of ConformanceRunner.kt for the
// same LargeClass detekt budget reason as ConformanceRunnerFiles.kt (mirrors the macOS codec's
// own ConformanceRunner+Photos.swift split).

/** `photos-encoding` category (E41-01): decodes the raw message bytes each vector describes
 * (`input.messageHex` — see protocol/vectors/README.md) with the real generated Photos message
 * types (`protocol/proto/tandem/v1/photos.proto`), selected by `input.kind`. */
internal fun photosEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val kind = input.getValue("kind").jsonPrimitive.content
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    return when (kind) {
        "photoPageResult" -> photoPageResultOutcome(id, messageBytes, vector)
        "thumbResult" -> thumbResultOutcome(id, messageBytes, vector)
        "originalRequest" -> originalRequestOutcome(id, messageBytes, vector)
        "photoError" -> photoErrorOutcome(id, messageBytes, vector)
        else -> error("unsupported photos-encoding kind: $kind")
    }
}

private fun photoPageResultOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            PhotoPageResult.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "photos-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedItems = expected.getValue("items").jsonArray
    val expectedNextCursor = expected.getValue("nextCursor").jsonPrimitive.content
    val expectedAccess = expected.getValue("access").jsonPrimitive.content
    val itemsMatch =
        decoded.itemsCount == expectedItems.size &&
            decoded.itemsList.zip(expectedItems).all { (actualItem, expectedElement) ->
                val expectedItem = expectedElement.jsonObject
                actualItem.id == expectedItem.getValue("id").jsonPrimitive.content &&
                    actualItem.takenAt ==
                    expectedItem
                        .getValue("takenAt")
                        .jsonPrimitive.content
                        .toLong() &&
                    actualItem.width ==
                    expectedItem
                        .getValue("width")
                        .jsonPrimitive.content
                        .toInt() &&
                    actualItem.height ==
                    expectedItem
                        .getValue("height")
                        .jsonPrimitive.content
                        .toInt()
            }
    val passed =
        itemsMatch &&
            decoded.nextCursor == expectedNextCursor &&
            decoded.access.name == expectedAccess
    val expectedDescription = "items=${expectedItems.size} nextCursor=$expectedNextCursor access=$expectedAccess"
    val actualDescription = "items=${decoded.itemsCount} nextCursor=${decoded.nextCursor} access=${decoded.access.name}"
    return VectorOutcome(
        id,
        "photos-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}

private fun thumbResultOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            ThumbResult.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "photos-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedId = expected.getValue("id").jsonPrimitive.content
    val expectedPngBytesHex = expected.getValue("pngBytesHex").jsonPrimitive.content
    val actualPngBytesHex = decoded.pngBytes.toByteArray().toHex()
    val passed = decoded.id == expectedId && actualPngBytesHex == expectedPngBytesHex
    return VectorOutcome(
        id,
        "photos-encoding",
        if (passed) "pass" else "fail",
        expectedPngBytesHex,
        actualPngBytesHex,
    )
}

private fun originalRequestOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            OriginalRequest.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "photos-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedId = expected.getValue("id").jsonPrimitive.content
    val expectedTransferId = expected.getValue("transferId").jsonPrimitive.content
    val passed = decoded.id == expectedId && decoded.transferId == expectedTransferId
    val expectedDescription = "id=$expectedId transferId=$expectedTransferId"
    val actualDescription = "id=${decoded.id} transferId=${decoded.transferId}"
    return VectorOutcome(
        id,
        "photos-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}

private fun photoErrorOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        try {
            PhotoError.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "photos-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedKind = expected.getValue("kind").jsonPrimitive.content
    val expectedRef = expected.getValue("ref").jsonPrimitive.content
    val expectedReason = expected.getValue("reason").jsonPrimitive.content
    val passed =
        decoded.kind.name == expectedKind &&
            decoded.ref == expectedRef &&
            decoded.reason.name == expectedReason
    val expectedDescription = "kind=$expectedKind ref=$expectedRef reason=$expectedReason"
    val actualDescription = "kind=${decoded.kind.name} ref=${decoded.ref} reason=${decoded.reason.name}"
    return VectorOutcome(
        id,
        "photos-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}
