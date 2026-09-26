package dev.tandem.core.pairing.conformance

import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Channel
import kotlinx.coroutines.runInterruptible
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/**
 * E15-01: minimal, self-contained copies of the wire-format/loading helpers each per-category
 * conformance test (`FrameVectorTestSupport.kt` et al.) already has in its own Gradle module's test
 * source set. Those source sets are not visible from `core/pairing`'s test source set (Gradle does
 * not expose one module's test classpath to another), so [ConformanceRunner] carries its own copy
 * rather than reaching across module boundaries -- mirrors the existing duplication between, e.g.,
 * `FrameVectorTestSupport.hexToBytes` and `SpkiFingerprintVectorTestSupport.hexToBytes`.
 */
private const val CHANNEL_FIELD_NUMBER = 1
private const val SEQ_FIELD_NUMBER = 2
private const val ACK_FIELD_NUMBER = 3
private const val RING_FIELD_NUMBER = 21

fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

/** A [FrameSource] over exactly [frameBytes], with no trailing EOF marker. */
fun sourceFor(frameBytes: ByteArray): FrameSource {
    val pipe = InMemoryDuplexPipe(capacity = maxOf(frameBytes.size, 1))
    pipe.endpointA.output.write(frameBytes)
    pipe.endpointA.closeGracefully()
    return FrameSource { buffer, offset, length ->
        runInterruptible { pipe.endpointB.input.read(buffer, offset, length) }
    }
}

private fun varint(value: Long): ByteArray {
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

private fun tag(
    fieldNumber: Int,
    wireType: Int,
): ByteArray = varint((fieldNumber.toLong() shl 3) or wireType.toLong())

private fun fieldVarint(
    fieldNumber: Int,
    value: Long,
): ByteArray = tag(fieldNumber, 0) + varint(value)

private fun fieldLenDelimited(
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
