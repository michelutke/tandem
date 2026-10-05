package dev.tandem.core.pairing.conformance

import com.google.protobuf.InvalidProtocolBufferException
import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.protocol.v1.MediaFrame
import dev.tandem.protocol.v1.MediaMessage
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E61-01: media-frame-encoding conformance vector handlers, split out of ConformanceRunner.kt for the
// same LargeClass detekt budget reason as ConformanceRunnerMedia.kt (mirrors the macOS codec's own
// ConformanceRunner+MediaFrame.swift split).

private const val CATEGORY = "media-frame-encoding"
private const val MAX_FRAGMENTS = 8
private const val FRAGMENT_VIOLATION = "MALFORMED_FRAME:FRAGMENT_VIOLATION"

/** `media-frame-encoding` category (E61-01): decodes `MediaMessage` bodies (`input.messageHex`),
 * reassembles `MediaFrame` fragment sequences (`input.messagesHex`) and runs prefix-only oversize
 * frames (`input.frameHex`) through the framing layer; see protocol/vectors/README.md. */
internal fun mediaFrameEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    return try {
        when (val kind = input.getValue("kind").jsonPrimitive.content) {
            "mediaFrameLengthPrefix" -> {
                mediaFramePrefixOutcome(id, input, vector)
            }

            "mediaFrameSequence" -> {
                mediaFrameSequenceOutcome(id, input, vector)
            }

            "mediaFormat", "mediaFrame", "keyframeRequest", "rotationChanged" -> {
                mediaMessageOutcome(id, kind, input, vector)
            }

            else -> {
                error("unsupported media-frame-encoding kind: $kind")
            }
        }
    } catch (e: InvalidProtocolBufferException) {
        VectorOutcome(id, CATEGORY, "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun mediaFramePrefixOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val decoded =
        runBlocking {
            FrameDecoder.decodeFrame(sourceFor(hexToBytes(input.getValue("frameHex").jsonPrimitive.content)))
        }
    val rejected = decoded as? DecodeResult.Rejected
    val closeCode = vector.getValue("closeCode").jsonPrimitive.content
    val expected = "$closeCode:${vector.getValue("localReason").jsonPrimitive.content}"
    val actual = rejected?.let { "${it.closeCode.name}:${it.reason.name}" } ?: decoded.toString()
    return VectorOutcome(id, CATEGORY, if (actual == expected) "pass" else "fail", expected, actual)
}

private fun mediaMessageOutcome(
    id: String,
    kind: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val bytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val decoded = MediaMessage.parseFrom(bytes)
    val expected = vector.getValue("expected").jsonObject
    val expectedSummary = expected.getValue("summary").jsonPrimitive.content
    val actualSummary = mediaMessageSummary(kind, decoded)
    val passed =
        actualSummary == expectedSummary &&
            decoded.toByteArray().contentEquals(bytes) &&
            sha256Hex(bytes) == expected.getValue("messageSha256").jsonPrimitive.content
    return VectorOutcome(id, CATEGORY, if (passed) "pass" else "fail", expectedSummary, actualSummary)
}

private fun mediaMessageSummary(
    kind: String,
    message: MediaMessage,
): String =
    when {
        kind == "mediaFormat" && message.hasMediaFormat() -> {
            message.mediaFormat.let { "codec=${it.codecValue}|width=${it.width}|height=${it.height}|fps=${it.fps}" }
        }

        kind == "mediaFrame" && message.hasMediaFrame() -> {
            message.mediaFrame.let {
                "pts=${it.pts}|flags=${it.flags}|dataLength=${it.data.size()}" +
                    "|index=${it.fragmentIndex}|count=${it.fragmentCount}"
            }
        }

        kind == "keyframeRequest" && message.hasKeyframeRequest() -> {
            "empty"
        }

        kind == "rotationChanged" && message.hasRotationChanged() -> {
            "orientation=${message.rotationChanged.orientationValue}"
        }

        else -> {
            "payload=${message.payloadCase}"
        }
    }

private fun mediaFrameSequenceOutcome(
    id: String,
    input: JsonObject,
    vector: JsonObject,
): VectorOutcome {
    val fragments = input.getValue("messagesHex").jsonArray.toFragments()
    val result = reassemble(fragments)
    if ("expected" in vector) {
        val expected = vector.getValue("expected").jsonObject
        val expectedSha = expected.getValue("reassembledSha256").jsonPrimitive.content
        val expectedLength =
            expected
                .getValue("reassembledLength")
                .jsonPrimitive.content
                .toInt()
        val reassembled = result.accessUnit
        val passed =
            reassembled != null && sha256Hex(reassembled) == expectedSha && reassembled.size == expectedLength
        val actual = reassembled?.let { "length=${it.size} sha256=${sha256Hex(it)}" } ?: "rejected@${result.rejectedAt}"
        val expectedText = "length=$expectedLength sha256=$expectedSha"
        return VectorOutcome(id, CATEGORY, if (passed) "pass" else "fail", expectedText, actual)
    }
    val expectedIndex =
        input
            .getValue("rejectedAtIndex")
            .jsonPrimitive.content
            .toInt()
    val expected = "$FRAGMENT_VIOLATION@$expectedIndex"
    val actual = if (result.rejectedAt != null) "$FRAGMENT_VIOLATION@${result.rejectedAt}" else "accepted"
    return VectorOutcome(id, CATEGORY, if (actual == expected) "pass" else "fail", expected, actual)
}

private fun JsonArray.toFragments(): List<MediaFrame> =
    map { MediaMessage.parseFrom(hexToBytes(it.jsonPrimitive.content)).mediaFrame }

private class Reassembly(
    val accessUnit: ByteArray?,
    val rejectedAt: Int?,
)

/** SPEC.md #media-frame-semantics fragmentation rule over one access unit's fragments. */
private fun reassemble(fragments: List<MediaFrame>): Reassembly {
    val buffer = java.io.ByteArrayOutputStream()
    val head = fragments.firstOrNull()
    val violation = fragments.indices.firstOrNull { violatesFragmentRule(head, fragments[it], it) }
    val completeAt = fragments.indexOfFirst { it.fragmentIndex == it.fragmentCount - 1 }
    return when {
        violation != null && (completeAt < 0 || violation <= completeAt) -> {
            Reassembly(null, violation)
        }

        completeAt < 0 -> {
            Reassembly(null, null)
        }

        else -> {
            fragments.take(completeAt + 1).forEach { it.data.writeTo(buffer) }
            Reassembly(buffer.toByteArray(), null)
        }
    }
}

private fun violatesFragmentRule(
    head: MediaFrame?,
    fragment: MediaFrame,
    position: Int,
): Boolean =
    if (position == 0 || head == null) {
        fragment.fragmentCount !in 1..MAX_FRAGMENTS || fragment.fragmentIndex != 0
    } else {
        fragment.pts != head.pts ||
            fragment.fragmentCount != head.fragmentCount ||
            fragment.fragmentIndex != position
    }
