package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * E21-06 tdd:
 *   ci: discoveryTrustBoundaryLint_fixtureCallingTrustStoreWrite_reportsViolation
 *
 * Fixtures are permanent files under tools/lint-fixtures/discovery-trust-boundary/.
 * `core/discovery` is the only module the rule is applied to (android/config/detekt/detekt.yml).
 */
class DiscoveryTrustBoundaryTest {
    @Test
    fun discoveryTrustBoundaryLint_fixtureCallingTrustStoreWrite_reportsViolation() {
        val findings = DiscoveryTrustBoundary().compileAndLint(fixture("DiscoveryTrustStoreWriteFixture.kt"))

        assertTrue(findings.isNotEmpty())
        assertTrue(findings.all { it.id == "DiscoveryTrustBoundary" })
    }

    @Test
    fun discoveryTrustBoundaryLint_fixtureUsingPinVerifier_reportsViolation() {
        val findings = DiscoveryTrustBoundary().compileAndLint(fixture("DiscoveryVerifierBypassFixture.kt"))

        assertTrue(findings.isNotEmpty())
        assertTrue(findings.all { it.id == "DiscoveryTrustBoundary" })
    }

    @Test
    fun discoveryTrustBoundaryLint_fullyQualifiedTrustStoreUse_reportsViolation() {
        val findings =
            DiscoveryTrustBoundary().compileAndLint(
                """
                package dev.tandem.core.discovery

                internal fun probe(store: dev.tandem.core.storage.trust.TrustStore) = store.toString()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
    }

    @Test
    fun discoveryTrustBoundaryLint_spkiFingerprintAndRotatingId_detektPasses() {
        val findings =
            DiscoveryTrustBoundary().compileAndLint(
                """
                package dev.tandem.core.discovery

                import dev.tandem.core.crypto.DiscoveryRotatingId
                import dev.tandem.core.crypto.SpkiFingerprint

                internal fun candidate(fingerprint: SpkiFingerprint): String = fingerprint.toString()
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    private fun fixture(name: String): String {
        val repoRoot = File(System.getProperty("user.dir"), "../../..").canonicalFile
        return File(repoRoot, "tools/lint-fixtures/discovery-trust-boundary/$name").readText()
    }
}
