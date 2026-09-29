package dev.tandem.harness.jvmclient.latency

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** E30-14 tdd: unit: latencyReport_twoHundredSamples_p95ByNearestRank */
class NearestRankPercentileTest {
    @Test
    fun latencyReport_twoHundredSamples_p95ByNearestRank() {
        // 200 samples of 1..200 ms, already in order -- nearest rank over 200 samples at the 95th
        // percentile is rank ceil(0.95 * 200) = 190, i.e. the 190th smallest value: 190.
        val samples = (1..200).map { it.toLong() }

        assertEquals(190L, NearestRankPercentile.p95(samples))
    }

    @Test
    fun p95_singleSample_returnsThatSample() {
        assertEquals(42L, NearestRankPercentile.p95(listOf(42L)))
    }

    @Test
    fun p95_unsortedSamples_sortsBeforeRanking() {
        val samples = (200 downTo 1).map { it.toLong() }

        assertEquals(190L, NearestRankPercentile.p95(samples))
    }
}
