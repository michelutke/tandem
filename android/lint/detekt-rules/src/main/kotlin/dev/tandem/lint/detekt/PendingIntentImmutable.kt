package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtCallExpression
import org.jetbrains.kotlin.psi.KtDotQualifiedExpression
import org.jetbrains.kotlin.psi.KtExpression
import org.jetbrains.kotlin.psi.KtNamedFunction
import org.jetbrains.kotlin.psi.psiUtil.getParentOfType
import java.io.File

/**
 * E00-28: every `PendingIntent.getActivity/getBroadcast/getService/getForegroundService` call
 * must pass `FLAG_IMMUTABLE` and wrap an explicit-component `Intent` (invariants 1, 4 — a
 * mutable or implicit-target PendingIntent can be redirected by another app to forge input into
 * Tandem). `FLAG_MUTABLE` is only accepted when the enclosing function is listed in
 * `tools/lint/pending-intent-mutable.allowlist`, naming the issue that justifies it.
 *
 * Syntactic limits (no type resolution available to a detekt rule; document per E00-28's "Android
 * Lint is heavier" note):
 *   - The Intent argument is recognized as explicit only when it is an inline
 *     `Intent(context, X::class.java)` (or `X::class`) constructor call, or an inline call chain
 *     ending in `.setClass(...)`/`.setComponent(...)`. An Intent built in a separate variable, a
 *     helper function, or a later statement is not tracked across statements and is reported as
 *     non-explicit.
 *   - The mutable-allowlist match is by containing file name + enclosing function simple name
 *     (no fully-qualified-name resolution), so a name collision across files is possible; that is
 *     an easy thing to catch in code review of the allowlist diff.
 */
class PendingIntentImmutable(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "PendingIntentImmutable",
            severity = Severity.Defect,
            description = "PendingIntent.get*() must pass FLAG_IMMUTABLE and an explicit-component Intent (invariants 1, 4).",
            debt = Debt.TWENTY_MINS,
        )

    private val mutableAllowlist: Set<String> by lazy {
        readAllowlist(valueOrDefault(MUTABLE_ALLOWLIST_PROPERTY, DEFAULT_MUTABLE_ALLOWLIST))
    }

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        val dotExpression = expression.parent as? KtDotQualifiedExpression ?: return
        if (dotExpression.selectorExpression !== expression) return
        if (dotExpression.receiverExpression.text.substringAfterLast('.') != "PendingIntent") return
        val callee = expression.calleeExpression?.text ?: return
        if (callee !in GET_METHODS) return

        checkFlags(expression, callee)
        checkIntentArgument(expression, callee)
    }

    private fun checkFlags(expression: KtCallExpression, callee: String) {
        val flagsText = expression.valueArguments.getOrNull(FLAGS_ARG_INDEX)?.getArgumentExpression()?.text.orEmpty()
        if (flagsText.contains("FLAG_IMMUTABLE")) return
        if (flagsText.contains("FLAG_MUTABLE") && isAllowlisted(expression)) return

        val reason =
            if (flagsText.contains("FLAG_MUTABLE")) {
                " (FLAG_MUTABLE needs an entry in tools/lint/pending-intent-mutable.allowlist naming the issue)"
            } else {
                ""
            }
        report(CodeSmell(issue, Entity.from(expression), "PendingIntent.$callee() must pass FLAG_IMMUTABLE$reason."))
    }

    private fun checkIntentArgument(expression: KtCallExpression, callee: String) {
        val intentArg = expression.valueArguments.getOrNull(INTENT_ARG_INDEX)?.getArgumentExpression() ?: return
        if (isExplicitComponentIntent(intentArg)) return

        report(
            CodeSmell(
                issue,
                Entity.from(expression),
                "PendingIntent.$callee() must wrap an explicit-component Intent " +
                    "(Intent(context, X::class.java), or a chain ending in .setClass/.setComponent).",
            ),
        )
    }

    private fun isAllowlisted(expression: KtCallExpression): Boolean {
        val function = expression.getParentOfType<KtNamedFunction>(strict = true) ?: return false
        val name = function.name ?: return false
        return "${expression.containingFile.name}#$name" in mutableAllowlist
    }

    private fun isExplicitComponentIntent(expression: KtExpression): Boolean {
        var current = expression
        while (current is KtDotQualifiedExpression) {
            val calleeName = (current.selectorExpression as? KtCallExpression)?.calleeExpression?.text
            if (calleeName == "setClass" || calleeName == "setComponent") return true
            current = current.receiverExpression
        }
        val call = current as? KtCallExpression ?: return false
        if (call.calleeExpression?.text != "Intent") return false
        return call.valueArguments.size >= 2 && call.valueArguments.any { it.text.contains("::class") }
    }

    private fun readAllowlist(path: String): Set<String> {
        val configured = File(path)
        val file = if (configured.isAbsolute) configured else File(System.getProperty("user.dir"), path)
        if (!file.isFile) return emptySet()
        return file.readLines()
            .map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapTo(LinkedHashSet()) { it.substringBefore(' ') }
    }

    private companion object {
        const val MUTABLE_ALLOWLIST_PROPERTY = "mutableAllowlistFile"
        const val DEFAULT_MUTABLE_ALLOWLIST = "../tools/lint/pending-intent-mutable.allowlist"
        val GET_METHODS = setOf("getActivity", "getBroadcast", "getService", "getForegroundService")
        const val INTENT_ARG_INDEX = 2
        const val FLAGS_ARG_INDEX = 3
    }
}
