package dev.tandem.core.protocol

import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest

/**
 * Shared helpers for reading `protocol/vectors/frame-encoding.json` (E01-19) and reconstructing
 * the exact bytes an `envelopeRecipe` describes (protocol/vectors/README.md's "Compact recipes"
 * section) — used by both [FrameEncoderTest] (E11-01) and [FrameDecoderTest] (E11-02) so the
 * loading and recipe-reconstruction logic exists in exactly one place.
 */
const val LENGTH_PREFIX_BYTES = 4
const val CHANNEL_FIELD_NUMBER = 1
const val SEQ_FIELD_NUMBER = 2
const val ACK_FIELD_NUMBER = 3
const val RING_FIELD_NUMBER = 21
const val FILLER_FIELD_NUMBER = 500_000
const val RECIPE_SOLVE_ITERATIONS = 16

fun loadVectorsFile(): JsonObject {
    val vectorsDir =
        System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
    val file = File(vectorsDir, "frame-encoding.json")
    return Json.parseToJsonElement(file.readText()).jsonObject
}

fun payloadCaseFor(kind: String): Envelope.PayloadCase =
    when (kind) {
        "ring" -> Envelope.PayloadCase.RING
        "deviceStatus" -> Envelope.PayloadCase.DEVICE_STATUS
        else -> error("unsupported payload kind: $kind")
    }

fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

// --- minimal protobuf wire-format encoder, mirroring tools/vectors/frame_encoding.py ---

fun varint(value: Long): ByteArray {
    require(value >= 0) { "varint must be non-negative" }
    val out = ByteArrayOutputStream()
    var remaining = value
    while (true) {
        val byte = (remaining and 0x7F).toInt()
        remaining = remaining ushr 7
        if (remaining != 0L) {
            out.write(byte or 0x80)
        } else {
            out.write(byte)
            return out.toByteArray()
        }
    }
}

fun tag(
    fieldNumber: Int,
    wireType: Int,
): ByteArray = varint((fieldNumber.toLong() shl 3) or wireType.toLong())

fun fieldVarint(
    fieldNumber: Int,
    value: Long,
): ByteArray = tag(fieldNumber, 0) + varint(value)

fun fieldLenDelimited(
    fieldNumber: Int,
    payload: ByteArray,
): ByteArray = tag(fieldNumber, 2) + varint(payload.size.toLong()) + payload

/** Reconstructs the exact bytes a manifest `envelopeRecipe` describes (protocol/vectors/README.md). */
fun buildEnvelopeFromRecipe(recipe: JsonObject): ByteArray {
    val out = ByteArrayOutputStream()
    val channel = Channel.valueOf(recipe.getValue("channel").jsonPrimitive.content)
    out.write(fieldVarint(CHANNEL_FIELD_NUMBER, channel.number.toLong()))

    val seq = recipe["seq"]?.jsonPrimitive?.long ?: 0L
    if (seq != 0L) out.write(fieldVarint(SEQ_FIELD_NUMBER, seq))
    val ack = recipe["ack"]?.jsonPrimitive?.long ?: 0L
    if (ack != 0L) out.write(fieldVarint(ACK_FIELD_NUMBER, ack))

    recipe["payload"]?.jsonObject?.let { payload ->
        val kind = payload.getValue("kind").jsonPrimitive.content
        require(kind == "ring") { "unsupported recipe payload kind: $kind" }
        out.write(fieldLenDelimited(RING_FIELD_NUMBER, ByteArray(0)))
    }

    recipe["filler"]?.jsonObject?.let { filler ->
        val fieldNumber = filler.getValue("fieldNumber").jsonPrimitive.int
        val fillByte =
            filler
                .getValue("fillByte")
                .jsonPrimitive.content
                .toInt(16)
                .toByte()
        val fillLength = filler.getValue("fillLength").jsonPrimitive.int
        out.write(fieldLenDelimited(fieldNumber, ByteArray(fillLength) { fillByte }))
    }

    return out.toByteArray()
}

/** Inverse of tools/vectors/frame_encoding.py's `solve_filler`: a filler field padding a
 * minimal Envelope out to exactly [targetTotal] bytes. */
fun solveFillerLength(
    fixedOverhead: Int,
    targetTotal: Int,
    fieldNumber: Int,
): Int {
    val tagLength = tag(fieldNumber, 2).size
    var varintLengthGuess = 1
    repeat(RECIPE_SOLVE_ITERATIONS) {
        val fillLength = targetTotal - fixedOverhead - tagLength - varintLengthGuess
        require(fillLength >= 0) { "target total too small for the fixed overhead and filler tag" }
        val actualLength = varint(fillLength.toLong()).size
        if (actualLength == varintLengthGuess) return fillLength
        varintLengthGuess = actualLength
    }
    error("failed to converge on a filler length")
}

/** A minimal Envelope (channel, seq, empty Ring payload) padded with an unrecognized
 * filler field to exactly [targetTotal] bytes, for tests that need a precise envelope size. */
fun buildEnvelopeWithFiller(
    channel: Channel,
    seq: Long,
    targetTotal: Int,
    fillerFieldNumber: Int,
): ByteArray {
    val base = ByteArrayOutputStream()
    base.write(fieldVarint(CHANNEL_FIELD_NUMBER, channel.number.toLong()))
    if (seq != 0L) base.write(fieldVarint(SEQ_FIELD_NUMBER, seq))
    base.write(fieldLenDelimited(RING_FIELD_NUMBER, ByteArray(0)))
    val baseBytes = base.toByteArray()

    val fillLength = solveFillerLength(baseBytes.size, targetTotal, fillerFieldNumber)
    val filler = fieldLenDelimited(fillerFieldNumber, ByteArray(fillLength))
    return baseBytes + filler
}
