package dev.tandem.core.protocol.fuzz

import com.code_intelligence.jazzer.junit.FuzzTest
import com.code_intelligence.jazzer.mutation.annotation.NotNull
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest.Companion.beLengthPrefix
import dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest.Companion.seedFrameBytes
import dev.tandem.core.protocol.loadVectorsFile
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import java.util.stream.Stream

/**
 * Jazzer fuzz target (E71-02) for the Envelope protobuf decoder behind [FrameDecoder]. Unlike
 * [FrameDecoderFuzzTest], which mutates the whole frame and mostly spends its budget on the
 * length prefix, every input here is treated as serialized Envelope bytes and given a matching
 * length prefix, so each execution reaches `Envelope.parseFrom` and the channel/payload checks.
 * Inputs over [FrameEncoder.MAX_ENVELOPE_BYTES] are skipped (the prefix check already covers them).
 *
 * Seeds are the envelope bytes of every `protocol/vectors/frame-encoding.json` vector (the frame
 * minus its 4-byte prefix). Driven by `tools/fuzz/campaign/run_campaign.sh jazzer ... envelope`.
 */
class EnvelopeDecoderFuzzTest {
    @MethodSource("seedEnvelopes")
    @FuzzTest
    fun fuzzTargetEnvelopeDecoder(
        @NotNull data: ByteArray,
    ) {
        if (data.isEmpty() || data.size > FrameEncoder.MAX_ENVELOPE_BYTES) return
        runBlocking { FrameDecoder.decodeFrame(OneShotFrameSource(beLengthPrefix(data.size.toLong()) + data)) }
    }

    companion object {
        private const val LENGTH_PREFIX_BYTES = 4

        @JvmStatic
        fun seedEnvelopes(): Stream<Arguments> =
            loadVectorsFile()
                .getValue("vectors")
                .jsonArray
                .map { seedFrameBytes(it.jsonObject.getValue("input").jsonObject) }
                .filter { it.size > LENGTH_PREFIX_BYTES }
                .map { Arguments.of(it.copyOfRange(LENGTH_PREFIX_BYTES, it.size)) }
                .stream()
    }
}
