package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.TestConfig
import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import kotlin.io.path.writeText

/**
 * E00-17 tdd:
 *   ci: releaseLogLint_clipboardTextInReleaseSourceSet_detektFails
 *   ci: releaseLogLint_redactedLengthOnlyLog_detektPasses
 *   ci: releaseLogLint_symbolAddedToSharedList_newCallFlagged
 *
 * `releaseLogLint_clipboardTextInDebugSourceSet_detektPasses` is a source-set exclusion (the
 * src/debug glob under `excludes` in detekt.yml), not rule logic, so it is covered by the shell
 * fixture in tools/lint/test/detekt_no_sensitive_release_log_test.sh instead of here.
 */
class NoSensitiveReleaseLogTest {
    @Test
    fun releaseLogLint_clipboardTextInReleaseSourceSet_detektFails() {
        val rule = ruleWithSymbols("clipboardText")

        val findings = rule.compileAndLint(
            """
            import android.util.Log

            fun logIt(clipboardText: String) {
                Log.d("clip", clipboardText)
            }
            """.trimIndent(),
        )

        assertEquals(1, findings.size)
        assertEquals("NoSensitiveReleaseLog", findings.single().id)
    }

    @Test
    fun releaseLogLint_redactedLengthOnlyLog_detektPasses() {
        val rule = ruleWithSymbols("clipboardText")

        val findings = rule.compileAndLint(
            """
            import android.util.Log

            fun logIt(clipboardText: String) {
                Log.d("clip", clipboardText.length.toString())
            }
            """.trimIndent(),
        )

        assertTrue(findings.isEmpty())
    }

    @Test
    fun releaseLogLint_symbolAddedToSharedList_newCallFlagged() {
        val code = """
            import android.util.Log

            fun logIt(replyText: String) {
                Log.d("reply", replyText)
            }
        """.trimIndent()

        assertTrue(ruleWithSymbols("clipboardText").compileAndLint(code).isEmpty())
        assertEquals(1, ruleWithSymbols("clipboardText", "replyText").compileAndLint(code).size)
    }

    @Test
    fun releaseLogLint_unrelatedLogCall_detektPasses() {
        val rule = ruleWithSymbols("clipboardText")

        val findings = rule.compileAndLint(
            """
            import android.util.Log

            fun logIt(requestId: String) {
                Log.d("net", requestId)
            }
            """.trimIndent(),
        )

        assertTrue(findings.isEmpty())
    }

    private fun ruleWithSymbols(vararg symbols: String): NoSensitiveReleaseLog {
        val file = Files.createTempFile("sensitive-symbols", ".txt")
        file.writeText(symbols.joinToString("\n"))
        file.toFile().deleteOnExit()
        return NoSensitiveReleaseLog(TestConfig("sensitiveSymbolsFile" to file.toAbsolutePath().toString()))
    }
}
