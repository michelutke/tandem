package dev.tandem.harness.jvmclient.latency

/**
 * E30-14: p95 over a set of latency samples using the nearest-rank method (SPEC.md's own metric
 * for the notification-latency harness) -- no interpolation between adjacent samples, unlike a
 * linear-interpolation percentile.
 */
object NearestRankPercentile {
    /**
     * The 95th percentile of [samples] by nearest rank: sorts ascending, then takes the value at
     * `ceil(0.95 * n)`, 1-indexed (SPEC.md #notification-latency-harness). Throws if [samples] is
     * empty -- there is no percentile of zero samples.
     */
    fun p95(samples: List<Long>): Long {
        require(samples.isNotEmpty()) { "p95 of an empty sample set is undefined" }
        val sorted = samples.sorted()
        val rank = Math.ceil(0.95 * sorted.size).toInt().coerceIn(1, sorted.size)
        return sorted[rank - 1]
    }
}
