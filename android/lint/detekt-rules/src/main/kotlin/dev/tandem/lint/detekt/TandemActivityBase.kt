package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtClass
import org.jetbrains.kotlin.psi.KtFile

/**
 * E00-28 tapjacking baseline: every class extending `Activity`, `ComponentActivity`,
 * `AppCompatActivity`, `FragmentActivity`, `ListActivity`, `PreferenceActivity` or
 * `NativeActivity` must extend `dev.tandem.app.TandemActivity` instead, so
 * `window.decorView.filterTouchesWhenObscured` is always set (invariants 1, 4). `TandemActivity`
 * itself is the one permitted direct subclass of those.
 *
 * Syntactic limits (no type resolution available to a detekt rule):
 *   - Matched by simple name, taken from the supertype text with any generic argument and package
 *     qualifier stripped (so `android.app.Activity()` and `Activity<Foo>()`, if that ever made
 *     sense, both match). An import alias is also resolved (`import
 *     androidx.fragment.app.FragmentActivity as FA` followed by `: FA()` is still caught by
 *     looking up `FA` against this file's own import directives) — but a `typealias`, or a class
 *     extending an unrelated type that happens to share one of these names with no corresponding
 *     import, is not resolved (false negative / false positive respectively). None of the latter
 *     exists in this codebase today.
 *   - This rule has no manifest-driven backstop: it only sees the source file being linted, so a
 *     supertype resolved indirectly (e.g. through a local `abstract class` this rule doesn't also
 *     flag) would slip through. The closed-form guarantee — every `<activity>` actually declared
 *     in the merged manifest really is assignable to `TandemActivity` — is a Robolectric test,
 *     `TandemActivityTest.everyDeclaredActivity_extendsTandemActivity`; this rule is fast feedback
 *     only, not the source of truth.
 */
class TandemActivityBase(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "TandemActivityBase",
            severity = Severity.Defect,
            description = "Activities must extend TandemActivity, not Activity/ComponentActivity/AppCompatActivity/" +
                "FragmentActivity/ListActivity/PreferenceActivity/NativeActivity directly (tapjacking " +
                "filterTouchesWhenObscured baseline, invariants 1, 4).",
            debt = Debt.TEN_MINS,
        )

    override fun visitClass(klass: KtClass) {
        super.visitClass(klass)
        if (klass.name == "TandemActivity") return

        val aliases = importAliases(klass)
        val superNames =
            klass.superTypeListEntries.mapNotNull { entry ->
                simpleName(entry.typeReference?.text)?.let { aliases[it] ?: it }
            }
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

    private fun simpleName(typeReferenceText: String?): String? =
        typeReferenceText?.substringBefore('<')?.substringAfterLast('.')?.takeIf { it.isNotEmpty() }

    // Maps an import alias (`import x.y.FragmentActivity as FA`) back to the real simple name, so
    // an aliased supertype reference is still recognized.
    private fun importAliases(klass: KtClass): Map<String, String> {
        val file = klass.containingFile as? KtFile ?: return emptyMap()
        return file.importDirectives.mapNotNull { import ->
            val alias = import.aliasName ?: return@mapNotNull null
            val original = import.importedFqName?.shortName()?.asString() ?: return@mapNotNull null
            alias to original
        }.toMap()
    }

    private companion object {
        val DIRECT_BASES =
            setOf(
                "Activity",
                "ComponentActivity",
                "AppCompatActivity",
                "FragmentActivity",
                "ListActivity",
                "PreferenceActivity",
                "NativeActivity",
            )
    }
}
