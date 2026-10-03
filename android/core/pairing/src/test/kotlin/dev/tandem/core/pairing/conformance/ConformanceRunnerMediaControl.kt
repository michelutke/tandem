package dev.tandem.core.pairing.conformance

import dev.tandem.protocol.v1.CapabilityUnavailable
import dev.tandem.protocol.v1.Next
import dev.tandem.protocol.v1.NowPlaying
import dev.tandem.protocol.v1.PlayPause
import dev.tandem.protocol.v1.Previous
import dev.tandem.protocol.v1.Stop
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E72-02: media-control-encoding conformance vector handlers, split out of ConformanceRunner.kt for the
// same LargeClass detekt budget reason as ConformanceRunnerFocus.kt (mirrors the macOS codec's own
// ConformanceRunner+MediaControl.swift split).

private const val ABSENT = "<absent>"

/** `media-control-encoding` category (E72-02): decodes the raw message bytes each vector describes
 * (`input.messageHex` -- see protocol/vectors/README.md) with the real generated media-control message
 * types (`protocol/proto/tandem/v1/media_control.proto`), selected by `input.kind`. */
internal fun mediaControlEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    val expected = vector.getValue("expected").jsonObject
    val expectedSummary = expected.getValue("summary").jsonPrimitive.content
    val expectedSha = expected.getValue("messageSha256").jsonPrimitive.content
    return try {
        val (actualSummary, reencoded) =
            decodeMediaControlMessage(input.getValue("kind").jsonPrimitive.content, messageBytes)
        val passed =
            actualSummary == expectedSummary &&
                reencoded.contentEquals(messageBytes) &&
                sha256Hex(messageBytes) == expectedSha
        VectorOutcome(id, "media-control-encoding", if (passed) "pass" else "fail", expectedSummary, actualSummary)
    } catch (e: com.google.protobuf.InvalidProtocolBufferException) {
        VectorOutcome(id, "media-control-encoding", "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun decodeMediaControlMessage(
    kind: String,
    messageBytes: ByteArray,
): Pair<String, ByteArray> =
    when (kind) {
        "nowPlaying" -> {
            val decoded = NowPlaying.parseFrom(messageBytes)
            val album = if (decoded.hasAlbum()) decoded.album else ABSENT
            val duration = if (decoded.hasDurationMs()) decoded.durationMs.toString() else ABSENT
            val summary =
                "title=${decoded.title}|artist=${decoded.artist}|state=${decoded.stateValue}" +
                    "|album=$album|durationMs=$duration"
            summary to decoded.toByteArray()
        }

        "playPause" -> {
            "empty" to PlayPause.parseFrom(messageBytes).toByteArray()
        }

        "next" -> {
            "empty" to Next.parseFrom(messageBytes).toByteArray()
        }

        "previous" -> {
            "empty" to Previous.parseFrom(messageBytes).toByteArray()
        }

        "stop" -> {
            "empty" to Stop.parseFrom(messageBytes).toByteArray()
        }

        "capabilityUnavailable" -> {
            val decoded = CapabilityUnavailable.parseFrom(messageBytes)
            "feature=${decoded.featureValue}" to decoded.toByteArray()
        }

        else -> {
            error("unsupported media-control-encoding kind: $kind")
        }
    }
