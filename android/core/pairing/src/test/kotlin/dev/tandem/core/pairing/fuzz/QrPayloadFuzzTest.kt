package dev.tandem.core.pairing.fuzz

import com.code_intelligence.jazzer.junit.FuzzTest
import com.code_intelligence.jazzer.mutation.annotation.NotNull
import dev.tandem.core.pairing.qr.QrPayloadParser
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import java.io.File
import java.util.stream.Stream

/**
 * Jazzer fuzz target (E71-03) for [QrPayloadParser], the Android QR pairing payload parser
 * (`tandem://pair?v=1&fp=...&s=...&a=...&p=...&n=...`; macOS only encodes, never parses). Only an
 * uncaught exception counts as a finding: `Accepted` and every `Rejected` are legitimate outcomes
 * already covered by `QrPayloadParserTest`.
 *
 * Inputs are decoded as UTF-8. Seeds are the `input.uri` of every `protocol/vectors/qr-payload.json` vector. Driven by
 * `tools/fuzz/campaign/run_campaign.sh jazzer ... qr`.
 */
class QrPayloadFuzzTest {
    @MethodSource("seedUris")
    @FuzzTest
    fun fuzzTargetQrPayloadParser(
        @NotNull data: ByteArray,
    ) {
        QrPayloadParser.parse(String(data, Charsets.UTF_8))
    }

    companion object {
        @JvmStatic
        fun seedUris(): Stream<Arguments> {
            val vectorsDir =
                System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
            return Json
                .parseToJsonElement(File(vectorsDir, "qr-payload.json").readText())
                .jsonObject
                .getValue("vectors")
                .jsonArray
                .map {
                    Arguments.of(
                        it.jsonObject
                            .getValue("input")
                            .jsonObject
                            .getValue("uri")
                            .jsonPrimitive.content
                            .toByteArray(),
                    )
                }.stream()
        }
    }
}
