package dev.tandem.core.pairing.conformance

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec

/**
 * E15-01: the conformance runner's own behavior, distinct from the per-category conformance suites
 * ([dev.tandem.core.protocol.FrameCodecConformanceTest] and friends) that already exercise each
 * vector category's codec/crypto implementation. Reuses those via [ConformanceRunner]'s category
 * table rather than duplicating their assertions.
 */
class ConformanceRunnerTest {
    @Test
    fun kotlinConformanceRunner_realVectorsDirectory_everyCategoryHandledOrDeferredAndSummaryPrinted() {
        val vectorsDirProperty =
            System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
        val vectorsDir = File(vectorsDirProperty)

        val outcomes = ConformanceRunner.run(vectorsDir)
        ConformanceRunner.assertAllPassed(outcomes)

        val diskCount = ConformanceRunner.countVectorsOnDisk(vectorsDir)
        val deferredCount = outcomes.count { it.outcome == "skipped" }
        val executedCount = outcomes.size - deferredCount

        assertEquals(diskCount, outcomes.size, "every vector on disk must produce exactly one outcome")
        assertEquals(diskCount - deferredCount, executedCount)
        println(
            "conformance: executed $executedCount vectors ($deferredCount deferred/skipped) out of $diskCount on disk",
        )

        val reportFile = File(vectorsDir.parentFile!!.parentFile, "tools/conformance/reports/android-report.json")
        ConformanceRunner.writeReport(outcomes, reportFile)
        assertTrue(reportFile.exists())
    }

    @Test
    fun kotlinConformanceRunner_corruptedExpectedValue_failsWithHexDiff(
        @TempDir tempDir: File,
    ) {
        val spkiDer =
            KeyPairGenerator
                .getInstance("EC")
                .apply { initialize(ECGenParameterSpec("secp256r1")) }
                .generateKeyPair()
                .public
                .encoded
        val correctFingerprintHex =
            dev.tandem.core.crypto
                .spkiFingerprint(spkiDer)
                .bytes
                .toHex()
        val corruptedFirstByte = if (correctFingerprintHex.startsWith("00")) "ff" else "00"
        val corruptedFingerprintHex = corruptedFirstByte + correctFingerprintHex.substring(2)

        File(tempDir, "spki-fingerprint.json").writeText(
            """
            {
              "category": "spki-fingerprint",
              "generatedBy": "test-fixture",
              "vectors": [
                {
                  "id": "corrupted-vector",
                  "description": "deliberately wrong expected fingerprint",
                  "input": { "spkiDerHex": "${spkiDer.toHex()}" },
                  "expected": { "fingerprintHex": "$corruptedFingerprintHex" }
                }
              ]
            }
            """.trimIndent(),
        )

        val outcomes = ConformanceRunner.run(tempDir)
        val failure = outcomes.single { it.outcome == "fail" }
        assertEquals("corrupted-vector", failure.id)
        assertEquals(corruptedFingerprintHex, failure.expected)
        assertEquals(correctFingerprintHex, failure.actual)

        val thrown = assertThrows(ConformanceFailure::class.java) { ConformanceRunner.assertAllPassed(outcomes) }
        assertTrue(thrown.message!!.contains("corrupted-vector"), thrown.message)
        assertTrue(thrown.message!!.contains(corruptedFingerprintHex), thrown.message)
        assertTrue(thrown.message!!.contains(correctFingerprintHex), thrown.message)
    }

    @Test
    fun kotlinConformanceRunner_unknownVectorCategory_failsNamingCategory(
        @TempDir tempDir: File,
    ) {
        File(tempDir, "bogus.json").writeText(
            """
            {
              "category": "bogus-category",
              "generatedBy": "test-fixture",
              "vectors": [
                { "id": "bogus-vector", "description": "n/a", "input": {}, "expected": {} }
              ]
            }
            """.trimIndent(),
        )

        val thrown =
            assertThrows(UnknownVectorCategoryException::class.java) {
                ConformanceRunner.run(tempDir)
            }
        assertTrue(thrown.message!!.contains("bogus-category"), thrown.message)
    }
}
