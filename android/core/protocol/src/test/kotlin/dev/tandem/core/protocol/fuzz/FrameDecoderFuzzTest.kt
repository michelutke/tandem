package dev.tandem.core.protocol.fuzz

import com.code_intelligence.jazzer.junit.FuzzTest
import com.code_intelligence.jazzer.mutation.annotation.NotNull
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.buildEnvelopeFromRecipe
import dev.tandem.core.protocol.hexToBytes
import dev.tandem.core.protocol.loadVectorsFile
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import java.util.stream.Stream
import kotlin.math.min

/**
 * Jazzer fuzz target (E15-13) for [FrameDecoder.decodeFrame], the real frame/envelope parser.
 * Feeds raw fuzzer-mutated bytes through [OneShotFrameSource], a minimal one-shot adapter over
 * the [FrameSource] seam (mirrors a socket that delivers exactly these bytes then hits EOF).
 * [dev.tandem.core.protocol.DecodeResult.Frame], `.Rejected` and `.EndOfStream` are all legitimate
 * outcomes already covered by `FrameDecoderTest` (E11-02) — this target only cares whether
 * `decodeFrame` throws an exception it doesn't itself catch (it already catches
 * `InvalidProtocolBufferException` and turns it into `Rejected(DECODE_FAILED)`), which Jazzer
 * reports as a finding.
 *
 * Seeded from the E01-19 corpus (protocol/vectors/frame-encoding.json) via [seedFrames], reusing
 * `FrameVectorTestSupport`'s vector loading and recipe reconstruction (shared with
 * `FrameEncoderTest`/`FrameDecoderTest`) rather than duplicating it. In regression mode (the
 * default, no `JAZZER_FUZZ`), Jazzer replays every seed as a parameterized case — this is how
 * `ci: jazzerFrameTarget_seedCorpusReplay_zeroCrashes` is satisfied by the ordinary `./gradlew
 * test` run. In fuzzing mode (`JAZZER_FUZZ=1`, driven by `tools/fuzz/jazzer/smoke.sh`), the seeds
 * additionally guide mutation.
 */
class FrameDecoderFuzzTest {
    @MethodSource("seedFrames")
    @FuzzTest
    fun fuzzTargetFrameDecoder(
        @NotNull data: ByteArray,
    ) {
        runBlocking { FrameDecoder.decodeFrame(OneShotFrameSource(data)) }
    }

    companion object {
        @JvmStatic
        fun seedFrames(): Stream<Arguments> =
            loadVectorsFile()
                .getValue("vectors")
                .jsonArray
                .map { Arguments.of(seedFrameBytes(it.jsonObject.getValue("input").jsonObject)) }
                .stream()

        // Unlike FrameDecoderTest's vector loading, this must NOT round-trip the envelope bytes
        // through Envelope.parseFrom/FrameEncoder: several vectors are deliberately malformed
        // (bad length prefixes, undecodable envelope bytes) to exercise FrameDecoder's rejection
        // paths, and parsing them as a well-formed Envelope would throw before the seed ever
        // reaches the fuzz target. So every vector's raw wire bytes are used verbatim instead.
        private fun seedFrameBytes(input: JsonObject): ByteArray {
            if ("frameHex" in input) return hexToBytes(input.getValue("frameHex").jsonPrimitive.content)

            val envelopeBytes = buildEnvelopeFromRecipe(input.getValue("envelopeRecipe").jsonObject)
            val lengthPrefix = input.getValue("lengthPrefix").jsonPrimitive.long
            return beLengthPrefix(lengthPrefix) + envelopeBytes
        }

        private fun beLengthPrefix(length: Long): ByteArray =
            byteArrayOf(
                (length ushr 24).toByte(),
                (length ushr 16).toByte(),
                (length ushr 8).toByte(),
                length.toByte(),
            )
    }
}

/** Adapts a fixed [bytes] array to [FrameSource]: delivers them once, then reports EOF (-1). */
private class OneShotFrameSource(
    private val bytes: ByteArray,
) : FrameSource {
    private var position = 0

    override suspend fun read(
        buffer: ByteArray,
        offset: Int,
        length: Int,
    ): Int {
        if (position >= bytes.size) return -1
        val n = min(length, bytes.size - position)
        System.arraycopy(bytes, position, buffer, offset, n)
        position += n
        return n
    }
}
