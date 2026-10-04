package dev.tandem.core.protocol.fuzz

import com.code_intelligence.jazzer.junit.FuzzTest
import com.code_intelligence.jazzer.mutation.annotation.NotNull
import dev.tandem.core.protocol.hexToBytes
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import java.io.File
import java.util.stream.Stream

/**
 * Jazzer fuzz target (E71-04): one generic target over every Kotlin domain message decoder in
 * [DomainFuzzRegistry]. `TANDEM_FUZZ_MESSAGE=<proto file stem>` (e.g. `media_control`) picks the
 * proto file; unset, every registry entry runs (regression replay of all seeds). Only an uncaught
 * exception counts as a finding: `InvalidProtocolBufferException` is a legitimate rejection.
 *
 * Seeds are every `messageHex`/`frameHex` (and `messagesHex`/`messageHexes` list) value in the
 * `protocol/vectors` files the selected entry lists. Driven by
 * `tools/fuzz/campaign/run_campaign.sh jazzer ... domain`.
 */
class DomainDecoderFuzzTest {
    @MethodSource("seeds")
    @FuzzTest
    fun fuzzTargetDomainDecoder(
        @NotNull data: ByteArray,
    ) {
        selectedEntries().forEach { it.decode(data) }
    }

    companion object {
        private const val MESSAGE_ENV = "TANDEM_FUZZ_MESSAGE"
        private val SEED_KEYS = setOf("messageHex", "frameHex", "messagesHex", "messageHexes")

        private fun selectedEntries(): List<DomainFuzzEntry> {
            val message = System.getenv(MESSAGE_ENV)?.takeIf { it.isNotEmpty() } ?: return DomainFuzzRegistry.entries
            val entry = DomainFuzzRegistry.entry(message) ?: error("no domain fuzz registry entry for $message.proto")
            return listOf(entry)
        }

        @JvmStatic
        fun seeds(): Stream<Arguments> {
            val vectorsDir =
                System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
            return selectedEntries()
                .flatMap { it.vectorFiles }
                .distinct()
                .flatMap { collectSeeds(Json.parseToJsonElement(File(vectorsDir, it).readText())) }
                .distinctBy { it.toList() }
                .map { Arguments.of(it) }
                .stream()
        }

        private fun collectSeeds(element: JsonElement): List<ByteArray> {
            if (element is JsonObject) {
                return element.entries.flatMap { (key, value) ->
                    if (key in SEED_KEYS) hexValues(value) else collectSeeds(value)
                }
            }
            if (element is JsonArray) return element.flatMap { collectSeeds(it) }
            return emptyList()
        }

        private fun hexValues(element: JsonElement): List<ByteArray> {
            if (element is JsonPrimitive) return listOf(hexToBytes(element.content))
            if (element is JsonArray) return element.flatMap { hexValues(it) }
            return emptyList()
        }
    }
}
