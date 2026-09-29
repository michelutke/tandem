package dev.tandem.harness.jvmclient.latency

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** E30-14 tdd: unit: latencyReportWriter_anyRun_containsOnlySequenceNumbersAndTimings */
class LatencyReportWriterTest {
    @Test
    fun latencyReportWriter_anyRun_containsOnlySequenceNumbersAndTimings() {
        val samples =
            listOf(
                LatencySample(sequence = 1, latencyMillis = 12),
                LatencySample(sequence = 2, latencyMillis = 34),
                LatencySample(sequence = 3, latencyMillis = 56),
            )

        val report = LatencyReportWriter.write(samples, p95Millis = 56)

        // Every line is either "<sequence> <latencyMillis>" or the "p95_ms <value>" summary --
        // digits and known keywords only, never arbitrary text such as a notification title/body
        // (invariant 7, CLAUDE.md).
        val lines = report.trimEnd('\n').split("\n")
        assertTrue(lines.isNotEmpty())
        lines.forEach { line ->
            assertTrue(
                line.matches(Regex("^\\d+ \\d+$")) || line.matches(Regex("^p95_ms \\d+$")),
                "unexpected line in latency report: \"$line\"",
            )
        }
    }
}
