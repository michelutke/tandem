package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.TestConfig
import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import kotlin.io.path.writeText

/**
 * E00-28 tdd:
 *   ci: pendingIntentLint_mutableWithoutAllowlistFixture_lintFails
 *   ci: pendingIntentLint_implicitIntentFixture_lintFails
 *
 * The corresponding shell fixtures in tools/lint/test/detekt_pending_intent_immutable_test.sh
 * additionally exercise this against a real `:app:detekt` Gradle run and the real
 * tools/lint/pending-intent-mutable.allowlist wiring; these are the rule-logic-only tests.
 */
class PendingIntentImmutableTest {
    @Test
    fun pendingIntentLint_mutableWithoutAllowlistFixture_lintFails() {
        val findings =
            rule().compileAndLint(
                """
                import android.app.PendingIntent
                import android.content.Context
                import android.content.Intent

                fun build(context: Context) {
                    PendingIntent.getActivity(
                        context,
                        0,
                        Intent(context, MainActivity::class.java),
                        PendingIntent.FLAG_MUTABLE,
                    )
                }
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("PendingIntentImmutable", findings.single().id)
    }

    @Test
    fun pendingIntentLint_implicitIntentFixture_lintFails() {
        val findings =
            rule().compileAndLint(
                """
                import android.app.PendingIntent
                import android.content.Context
                import android.content.Intent

                fun build(context: Context) {
                    PendingIntent.getBroadcast(
                        context,
                        0,
                        Intent("dev.tandem.app.ACTION_FOO"),
                        PendingIntent.FLAG_IMMUTABLE,
                    )
                }
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("PendingIntentImmutable", findings.single().id)
    }

    @Test
    fun pendingIntentLint_immutableExplicitIntent_lintPasses() {
        val findings =
            rule().compileAndLint(
                """
                import android.app.PendingIntent
                import android.content.Context
                import android.content.Intent

                fun build(context: Context) {
                    PendingIntent.getActivity(
                        context,
                        0,
                        Intent(context, MainActivity::class.java),
                        PendingIntent.FLAG_IMMUTABLE,
                    )
                }
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    @Test
    fun pendingIntentLint_mutableWithAllowlistEntry_lintPasses() {
        // detekt-test's compileAndLint always compiles the snippet as "Test.kt"
        // (io.github.detekt.test.utils.KtTestCompiler.TEST_FILENAME).
        val findings =
            rule("Test.kt#build").compileAndLint(
                """
                import android.app.PendingIntent
                import android.content.Context
                import android.content.Intent

                fun build(context: Context) {
                    PendingIntent.getService(
                        context,
                        0,
                        Intent(context, MainActivity::class.java),
                        PendingIntent.FLAG_MUTABLE,
                    )
                }
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    @Test
    fun pendingIntentLint_explicitComponentViaSetClass_lintPasses() {
        val findings =
            rule().compileAndLint(
                """
                import android.app.PendingIntent
                import android.content.Context
                import android.content.Intent

                fun build(context: Context) {
                    PendingIntent.getService(
                        context,
                        0,
                        Intent("dev.tandem.app.ACTION_FOO").setClass(context, MainActivity::class.java),
                        PendingIntent.FLAG_IMMUTABLE,
                    )
                }
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    private fun rule(vararg allowlistEntries: String): PendingIntentImmutable {
        val file = Files.createTempFile("pending-intent-mutable", ".allowlist")
        file.writeText(allowlistEntries.joinToString("\n"))
        file.toFile().deleteOnExit()
        return PendingIntentImmutable(TestConfig("mutableAllowlistFile" to file.toAbsolutePath().toString()))
    }
}
