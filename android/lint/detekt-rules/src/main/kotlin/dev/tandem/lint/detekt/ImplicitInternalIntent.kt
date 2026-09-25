package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.com.intellij.psi.PsiElement
import org.jetbrains.kotlin.psi.KtCallExpression
import org.jetbrains.kotlin.psi.KtDotQualifiedExpression

/**
 * E00-28: a single-String-action `Intent("...")` / `Intent(Intent.ACTION_X)` constructor call has
 * no explicit target; sent internally (broadcast, `start*`, `PendingIntent`) it can be
 * intercepted by another app (invariants 1, 4). Flagged unless the same call chain immediately
 * applies `.setPackage(...)`, `.setClass(...)` or `.setComponent(...)` to it.
 *
 * Syntactic limit: only the immediate call chain rooted at the `Intent(...)` call is analyzed
 * (same limitation as `PendingIntentImmutable`'s explicit-component check). An Intent finished off
 * in a separate `apply {}`/`also {}` block, or on a later statement of a `val`, is not tracked and
 * will not be flagged; such call sites should inline the `.setPackage`/`.setClass`/`.setComponent`
 * call or otherwise make the explicit target visible in the same expression.
 *
 * A genuinely external implicit Intent (`Intent(Intent.ACTION_VIEW)`, `Intent.ACTION_SEND`
 * sharing, `Intent(Settings.ACTION_*)`, ...) is expected to have no explicit target — suppress the
 * finding at the function with `@Suppress("ImplicitInternalIntent")` rather than adding a
 * meaningless `.setPackage(...)`.
 */
class ImplicitInternalIntent(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "ImplicitInternalIntent",
            severity = Severity.Defect,
            description = "Intent(action) has no explicit target (setPackage/setClass/setComponent); an " +
                "internal implicit Intent can be intercepted by another app (invariants 1, 4).",
            debt = Debt.TWENTY_MINS,
        )

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        if (expression.calleeExpression?.text != "Intent") return
        val arg = expression.valueArguments.singleOrNull()?.getArgumentExpression() ?: return
        // Only the single-String-action constructor is implicit; Intent(context, Class) and
        // Intent(action, uri) two-arg overloads are out of scope for this rule.
        if (arg.text.contains("::class")) return
        if (hasExplicitTargetInChain(expression)) return

        report(CodeSmell(issue, Entity.from(expression), "Intent(...) has no explicit target; add setPackage/setClass/setComponent."))
    }

    private fun hasExplicitTargetInChain(expression: KtCallExpression): Boolean {
        var node: PsiElement = expression
        while (true) {
            val parent = node.parent as? KtDotQualifiedExpression ?: return false
            if (parent.receiverExpression !== node) return false
            val calleeName = (parent.selectorExpression as? KtCallExpression)?.calleeExpression?.text
            if (calleeName == "setPackage" || calleeName == "setClass" || calleeName == "setComponent") return true
            node = parent
        }
    }
}
