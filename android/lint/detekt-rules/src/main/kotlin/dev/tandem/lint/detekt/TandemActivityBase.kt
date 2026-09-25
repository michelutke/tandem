package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtClass

/**
 * E00-28 tapjacking baseline: every class extending `Activity`, `ComponentActivity` or
 * `AppCompatActivity` must extend `dev.tandem.app.TandemActivity` instead, so
 * `window.decorView.filterTouchesWhenObscured` is always set (invariants 1, 4). `TandemActivity`
 * itself is the one permitted direct subclass of those three.
 *
 * Syntactic limit: matched by simple supertype name only (no type resolution available to a
 * detekt rule); a class extending an unrelated type that happens to share one of these three
 * names would be a false positive. None exists in this codebase.
 */
class TandemActivityBase(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "TandemActivityBase",
            severity = Severity.Defect,
            description = "Activities must extend TandemActivity, not Activity/ComponentActivity/AppCompatActivity " +
                "directly (tapjacking filterTouchesWhenObscured baseline, invariants 1, 4).",
            debt = Debt.TEN_MINS,
        )

    override fun visitClass(klass: KtClass) {
        super.visitClass(klass)
        if (klass.name == "TandemActivity") return

        val superNames = klass.superTypeListEntries.mapNotNull { it.typeReference?.text }
        if ("TandemActivity" in superNames) return

        val directBase = superNames.firstOrNull { it in DIRECT_BASES } ?: return
        report(
            CodeSmell(
                issue,
                Entity.from(klass),
                "`${klass.name}` extends $directBase directly; extend TandemActivity instead.",
            ),
        )
    }

    private companion object {
        val DIRECT_BASES = setOf("Activity", "ComponentActivity", "AppCompatActivity")
    }
}
