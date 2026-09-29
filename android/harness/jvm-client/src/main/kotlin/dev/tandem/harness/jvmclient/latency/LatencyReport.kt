package dev.tandem.harness.jvmclient.latency

/** One frame's round-trip latency (E30-14): a sequence number and a timing, nothing else. */
data class LatencySample(
    val sequence: Int,
    val latencyMillis: Long,
)

/**
 * E30-14: renders a latency run as text containing only sequence numbers and timings -- never
 * notification content (invariant 7, CLAUDE.md). One `<sequence> <latencyMillis>` line per
 * sample, in [samples]' own order, followed by a `p95_ms <value>` summary line.
 */
object LatencyReportWriter {
    fun write(
        samples: List<LatencySample>,
        p95Millis: Long,
    ): String =
        buildString {
            samples.forEach { sample -> appendLine("${sample.sequence} ${sample.latencyMillis}") }
            appendLine("p95_ms $p95Millis")
        }
}
