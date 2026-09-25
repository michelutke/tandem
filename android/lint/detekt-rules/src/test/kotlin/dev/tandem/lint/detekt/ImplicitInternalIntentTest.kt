package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.test.compileAndLint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ImplicitInternalIntentTest {
    @Test
    fun implicitInternalIntent_bareActionIntent_detektFails() {
        val findings =
            ImplicitInternalIntent().compileAndLint(
                """
                import android.content.Intent

                fun broadcast(): Intent = Intent("dev.tandem.app.ACTION_FOO")
                """.trimIndent(),
            )

        assertEquals(1, findings.size)
        assertEquals("ImplicitInternalIntent", findings.single().id)
    }

    @Test
    fun implicitInternalIntent_setPackageChained_detektPasses() {
        val findings =
            ImplicitInternalIntent().compileAndLint(
                """
                import android.content.Context
                import android.content.Intent

                fun broadcast(context: Context): Intent =
                    Intent("dev.tandem.app.ACTION_FOO").setPackage(context.packageName)
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }

    @Test
    fun implicitInternalIntent_explicitComponentConstructor_detektPasses() {
        val findings =
            ImplicitInternalIntent().compileAndLint(
                """
                import android.content.Context
                import android.content.Intent

                fun start(context: Context): Intent = Intent(context, MainActivity::class.java)
                """.trimIndent(),
            )

        assertTrue(findings.isEmpty())
    }
}
