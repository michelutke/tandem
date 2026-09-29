package dev.tandem.core.pairing.conformance

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.FileAccept
import dev.tandem.protocol.v1.FileChunk
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.FileReject
import dev.tandem.protocol.v1.FileResumeRequest
import dev.tandem.protocol.v1.fileChunk
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E40-01: files-encoding conformance vector handlers, split out of ConformanceRunner.kt
// purely to keep that object's LargeClass detekt budget (mirrors the macOS codec's own
// ConformanceRunner+Files.swift split).

/** FILES channel's FileChunk.data cap (docs/protocol/SPEC.md #files-channel "Chunking"): 256 KiB, 2^18. */
private const val MAX_FILE_CHUNK_BYTES = 262_144

/** `files-encoding` category (E40-01): decodes the raw message bytes each vector describes
 * (`input.messageHex`, or `input.dataRecipe` for the oversized-chunk vector — see
 * protocol/vectors/README.md) with the real generated FILES message types, selected by
 * `input.kind`. `fileChunk` vectors are additionally validated against the FILES channel's
 * 262,144-byte `data` cap (docs/protocol/SPEC.md #files-channel "Chunking") since protobuf's
 * `bytes` wire type has no inherent size limit of its own. */
internal fun filesEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val kind = input.getValue("kind").jsonPrimitive.content
    return when (kind) {
        "fileOffer" -> fileOfferOutcome(id, input, vector)
        "fileAccept" -> fileAcceptOutcome(id, input, vector)
        "fileReject" -> fileRejectOutcome(id, input, vector)
        "fileChunk" -> fileChunkOutcome(id, input, vector)
        "fileResumeRequest" -> fileResumeRequestOutcome(id, input, vector)
        else -> error("unsupported files-encoding kind: $kind")
    }
}

private fun fileOfferOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded =
        try {
            FileOffer.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "files-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedSha256 = expected.getValue("sha256Hex").jsonPrimitive.content
    val passed =
        decoded.id == expected.getValue("id").jsonPrimitive.content &&
            decoded.name == expected.getValue("name").jsonPrimitive.content &&
            decoded.size ==
            expected
                .getValue("size")
                .jsonPrimitive.content
                .toLong() &&
            decoded.mime == expected.getValue("mime").jsonPrimitive.content &&
            decoded.sha256.toByteArray().toHex() == expectedSha256
    return VectorOutcome(
        id,
        "files-encoding",
        if (passed) "pass" else "fail",
        expectedSha256,
        decoded.sha256.toByteArray().toHex(),
    )
}

private fun fileAcceptOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded =
        try {
            FileAccept.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "files-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expectedId =
        vector
            .getValue("expected")
            .jsonObject
            .getValue("id")
            .jsonPrimitive.content
    val passed = decoded.id == expectedId
    return VectorOutcome(
        id,
        "files-encoding",
        if (passed) "pass" else "fail",
        expectedId,
        decoded.id,
    )
}

private fun fileRejectOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded =
        try {
            FileReject.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "files-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedId = expected.getValue("id").jsonPrimitive.content
    val expectedReason = expected.getValue("reason").jsonPrimitive.content
    val passed = decoded.id == expectedId && decoded.reason.name == expectedReason
    val expectedDescription = "id=$expectedId reason=$expectedReason"
    val actualDescription = "id=${decoded.id} reason=${decoded.reason.name}"
    return VectorOutcome(
        id,
        "files-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}

private fun fileResumeRequestOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded =
        try {
            FileResumeRequest.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "files-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val expected = vector.getValue("expected").jsonObject
    val expectedId = expected.getValue("id").jsonPrimitive.content
    val expectedFromOffset =
        expected
            .getValue("fromOffset")
            .jsonPrimitive.content
            .toLong()
    val passed = decoded.id == expectedId && decoded.fromOffset == expectedFromOffset
    val expectedDescription = "id=$expectedId fromOffset=$expectedFromOffset"
    val actualDescription = "id=${decoded.id} fromOffset=${decoded.fromOffset}"
    return VectorOutcome(
        id,
        "files-encoding",
        if (passed) "pass" else "fail",
        expectedDescription,
        actualDescription,
    )
}

private fun fileChunkOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val messageBytes = fileChunkBytes(input)
    val decoded =
        try {
            FileChunk.parseFrom(messageBytes)
        } catch (e: Exception) {
            return VectorOutcome(
                id,
                "files-encoding",
                "fail",
                "decodable",
                "failed to decode: ${e::class.simpleName}",
            )
        }
    val dataByteLength = decoded.data.toByteArray().size
    val accepted = dataByteLength <= MAX_FILE_CHUNK_BYTES

    return if ("expected" in vector && !accepted) {
        VectorOutcome(id, "files-encoding", "fail", "accepted", "rejected: fileChunkPayloadTooLarge")
    } else if ("expected" in vector) {
        val expected = vector.getValue("expected").jsonObject
        val expectedId = expected.getValue("id").jsonPrimitive.content
        val expectedSeq =
            expected
                .getValue("seq")
                .jsonPrimitive.content
                .toLong()
        val expectedOffset =
            expected
                .getValue("offset")
                .jsonPrimitive.content
                .toLong()
        val expectedDataHex = expected.getValue("dataHex").jsonPrimitive.content
        val passed =
            decoded.id == expectedId &&
                decoded.seq == expectedSeq &&
                decoded.offset == expectedOffset &&
                decoded.data.toByteArray().toHex() == expectedDataHex
        val expectedDescription = "id=$expectedId seq=$expectedSeq offset=$expectedOffset"
        val actualDescription = "id=${decoded.id} seq=${decoded.seq} offset=${decoded.offset}"
        VectorOutcome(
            id,
            "files-encoding",
            if (passed) "pass" else "fail",
            expectedDescription,
            actualDescription,
        )
    } else {
        val expectedError = vector.getValue("expectedError").jsonPrimitive.content
        val actual = if (accepted) "accepted" else "fileChunkPayloadTooLarge"
        val outcome = if (actual == expectedError) "pass" else "fail"
        VectorOutcome(id, "files-encoding", outcome, expectedError, actual)
    }
}

private fun fileChunkBytes(input: JsonObject): ByteArray {
    input["messageHex"]?.jsonPrimitive?.content?.let { return hexToBytes(it) }

    val recipe = input.getValue("dataRecipe").jsonObject
    val fillByte = hexToBytes(recipe.getValue("fillByte").jsonPrimitive.content).first()
    val fillLength =
        recipe
            .getValue("fillLength")
            .jsonPrimitive.content
            .toInt()
    val data = ByteArray(fillLength) { fillByte }

    return fileChunk {
        this.id = input.getValue("id").jsonPrimitive.content
        this.seq =
            input
                .getValue("seq")
                .jsonPrimitive.content
                .toLong()
        this.offset =
            input
                .getValue("offset")
                .jsonPrimitive.content
                .toLong()
        this.data = ByteString.copyFrom(data)
    }.toByteArray()
}
