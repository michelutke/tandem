package dev.tandem.core.protocol.fuzz.fixture

import com.code_intelligence.jazzer.junit.FuzzTest
import com.code_intelligence.jazzer.mutation.annotation.NotNull

/**
 * A deliberately broken target, used only to self-test `tools/fuzz/jazzer/smoke.sh` (E15-13) —
 * it proves the wrapper's exit-code mapping and reproducer-saving logic independently of the real
 * `FrameDecoder` target in [dev.tandem.core.protocol.fuzz.FrameDecoderFuzzTest]. Lives in its own
 * `fixture` sub-package so it is never mistaken for production fuzzing.
 */
internal object PlantedCrasherTarget {
    private const val MAGIC_PREFIX = "JAZZER_CRASH_ME"

    /**
     * Throws once [data] starts with [MAGIC_PREFIX]. Each byte is compared by its own `if` — not
     * a loop, and not a single array-equality call — because libFuzzer/Jazzer's coverage-guided
     * search tracks *which code location* ran, not how many loop iterations it took: a loop body
     * re-executes the same one or two locations regardless of how many bytes already matched, so
     * it gives the fuzzer no signal that it is getting closer. Each unrolled comparison is its own
     * location, reached only once every earlier byte already matched, so passing one more byte is
     * itself new coverage — the standard idiom for a fuzzer-findable planted crash (mirrors
     * Jazzer's and libFuzzer's own example fuzz targets). That is also exactly why this trips
     * detekt's generic complexity/return-count rules below: they assume more branches and returns
     * mean the function is doing too much, which doesn't hold for a magic-byte check that must
     * stay unrolled.
     */
    @Suppress("CyclomaticComplexMethod", "ReturnCount")
    fun process(data: ByteArray) {
        if (data.size < MAGIC_PREFIX.length) return
        if (data[0] != MAGIC_PREFIX[0].code.toByte()) return
        if (data[1] != MAGIC_PREFIX[1].code.toByte()) return
        if (data[2] != MAGIC_PREFIX[2].code.toByte()) return
        if (data[3] != MAGIC_PREFIX[3].code.toByte()) return
        if (data[4] != MAGIC_PREFIX[4].code.toByte()) return
        if (data[5] != MAGIC_PREFIX[5].code.toByte()) return
        if (data[6] != MAGIC_PREFIX[6].code.toByte()) return
        if (data[7] != MAGIC_PREFIX[7].code.toByte()) return
        if (data[8] != MAGIC_PREFIX[8].code.toByte()) return
        if (data[9] != MAGIC_PREFIX[9].code.toByte()) return
        if (data[10] != MAGIC_PREFIX[10].code.toByte()) return
        if (data[11] != MAGIC_PREFIX[11].code.toByte()) return
        if (data[12] != MAGIC_PREFIX[12].code.toByte()) return
        if (data[13] != MAGIC_PREFIX[13].code.toByte()) return
        if (data[14] != MAGIC_PREFIX[14].code.toByte()) return
        error("planted crasher fixture: magic prefix detected (tools/fuzz/jazzer smoke self-test)")
    }
}

class PlantedCrasherFuzzTest {
    @FuzzTest
    fun fuzzPlantedCrasher(
        @NotNull data: ByteArray,
    ) {
        PlantedCrasherTarget.process(data)
    }
}
