package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * E00-28 tdd:
 *   ci: activityBaseClassLint_activityNotExtendingTandemActivity_lintFails
 *
 * The corresponding shell fixture in tools/lint/test/detekt_tandem_activity_base_test.sh
 * additionally exercises this against a real `:app:detekt` Gradle run; this is the rule-logic-only
 * test.
 */
class TandemActivityBaseTest {
    @Test
    fun activityBaseClassLint_activityNotExtendingTandemActivity_lintFails() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                import android.app.Activity

                class RogueActivity : Activity()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("TandemActivityBase", findings.single().id)
    }

    @Test
    fun activityBaseClassLint_componentActivityDirectly_lintFails() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                import androidx.activity.ComponentActivity

                class RogueActivity : ComponentActivity()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("TandemActivityBase", findings.single().id)
    }

    @Test
    fun activityBaseClassLint_extendsTandemActivity_lintPasses() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                import dev.tandem.app.TandemActivity

                class MainActivity : TandemActivity()
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    @Test
    fun activityBaseClassLint_tandemActivityItself_lintPasses() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                import android.app.Activity

                open class TandemActivity : Activity()
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    @Test
    fun activityBaseClassLint_fullyQualifiedSupertype_lintFails() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                class RogueActivity : android.app.Activity()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("TandemActivityBase", findings.single().id)
    }

    @Test
    fun activityBaseClassLint_fragmentActivityDirectly_lintFails() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                import androidx.fragment.app.FragmentActivity

                class RogueActivity : FragmentActivity()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("TandemActivityBase", findings.single().id)
    }

    @Test
    fun activityBaseClassLint_aliasedImport_lintFails() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                import androidx.fragment.app.FragmentActivity as FA

                class RogueActivity : FA()
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("TandemActivityBase", findings.single().id)
    }

    @Test
    fun activityBaseClassLint_unrelatedSupertype_lintPasses() {
        val findings =
            TandemActivityBase().compileAndLint(
                """
                open class Base

                class NotAnActivity : Base()
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }
}
