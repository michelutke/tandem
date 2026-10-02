package dev.tandem.core.pairing.conformance

import com.google.protobuf.ByteString
import dev.tandem.protocol.v1.MediaHello
import dev.tandem.protocol.v1.MediaTicketGrant
import dev.tandem.protocol.v1.RequestMediaTicket
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// E60-01: media-encoding conformance vector handlers, split out of ConformanceRunner.kt for the same
// LargeClass detekt budget reason as ConformanceRunnerCalls.kt (mirrors the macOS codec's own
// ConformanceRunner+Media.swift split).

private const val MEDIA_TICKET_LENGTH = 32

/** `media-encoding` category (E60-01): decodes the raw message bytes each vector describes
 * (`input.messageHex` -- see protocol/vectors/README.md) with the real generated media-ticket message
 * types (`protocol/proto/tandem/v1/media.proto`, `control.proto`), selected by `input.kind`. */
internal fun mediaEncodingOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val messageBytes = hexToBytes(input.getValue("messageHex").jsonPrimitive.content)
    return try {
        when (val kind = input.getValue("kind").jsonPrimitive.content) {
            "requestMediaTicket" -> requestMediaTicketOutcome(id, messageBytes, vector)
            "mediaTicketGrant" -> mediaTicketGrantOutcome(id, messageBytes, vector)
            "mediaHello" -> mediaHelloOutcome(id, messageBytes, vector)
            else -> error("unsupported media-encoding kind: $kind")
        }
    } catch (e: com.google.protobuf.InvalidProtocolBufferException) {
        VectorOutcome(id, "media-encoding", "fail", "decodable", "failed to decode: ${e::class.simpleName}")
    }
}

private fun requestMediaTicketOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded = RequestMediaTicket.parseFrom(messageBytes)
    val expectedSha =
        vector
            .getValue("expected")
            .jsonObject
            .getValue("messageSha256")
            .jsonPrimitive.content
    val passed = decoded.toByteArray().contentEquals(messageBytes) && sha256Hex(messageBytes) == expectedSha
    return VectorOutcome(
        id,
        "media-encoding",
        if (passed) "pass" else "fail",
        "sha256=$expectedSha",
        "sha256=${sha256Hex(messageBytes)}",
    )
}

private fun mediaTicketGrantOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded = MediaTicketGrant.parseFrom(messageBytes)
    val expected = vector.getValue("expected").jsonObject
    val expectedTicket = hexToBytes(expected.getValue("ticketHex").jsonPrimitive.content)
    val expectedExpiresAt =
        expected
            .getValue("expiresAt")
            .jsonPrimitive.content
            .toLong()
    val passed =
        decoded.ticket == ByteString.copyFrom(expectedTicket) &&
            decoded.expiresAt == expectedExpiresAt &&
            decoded.toByteArray().contentEquals(messageBytes) &&
            sha256Hex(messageBytes) == expected.getValue("messageSha256").jsonPrimitive.content
    return VectorOutcome(
        id,
        "media-encoding",
        if (passed) "pass" else "fail",
        "ticketLength=${expectedTicket.size} expiresAt=$expectedExpiresAt",
        "ticketLength=${decoded.ticket.size()} expiresAt=${decoded.expiresAt}",
    )
}

private fun mediaHelloOutcome(
    id: String,
    messageBytes: ByteArray,
    vector: JsonObject,
): VectorOutcome {
    val decoded = MediaHello.parseFrom(messageBytes)
    val rejected = decoded.ticket.size() != MEDIA_TICKET_LENGTH
    if ("expected" in vector) {
        val expected = vector.getValue("expected").jsonObject
        val passed =
            !rejected &&
                decoded.ticket ==
                ByteString.copyFrom(
                    hexToBytes(expected.getValue("ticketHex").jsonPrimitive.content),
                ) &&
                decoded.toByteArray().contentEquals(messageBytes) &&
                sha256Hex(messageBytes) == expected.getValue("messageSha256").jsonPrimitive.content
        return VectorOutcome(
            id,
            "media-encoding",
            if (passed) "pass" else "fail",
            "accepted",
            if (rejected) "ticketRejected" else "accepted",
        )
    }
    val expectedError = vector.getValue("expectedError").jsonPrimitive.content
    val actual = if (rejected) "ticketRejected" else "accepted"
    return VectorOutcome(id, "media-encoding", if (actual == expectedError) "pass" else "fail", expectedError, actual)
}
