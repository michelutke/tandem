package dev.tandem.harness.jvmclient.latency

import java.io.File

/**
 * E30-14: reads `<sequence> <latencyMillis>` pairs (one per line) from the file at `args[0]`,
 * computes their p95 via [NearestRankPercentile.p95] (nearest-rank method), and prints
 * [LatencyReportWriter]'s report to stdout -- sequence numbers and timings only, never
 * notification content (invariant 7) -- for `tools/harness/integration/e30-14.sh` to parse and
 * assert against.
 */
fun main(args: Array<String>) {
    val inputFile = File(args.single())
    val samples =
        inputFile.readLines()
            .filter { it.isNotBlank() }
            .map { line ->
                val (sequence, latencyMillis) = line.trim().split(Regex("\\s+"))
                LatencySample(sequence.toInt(), latencyMillis.toLong())
            }
    val p95Millis = NearestRankPercentile.p95(samples.map { it.latencyMillis })
    print(LatencyReportWriter.write(samples, p95Millis))
}
