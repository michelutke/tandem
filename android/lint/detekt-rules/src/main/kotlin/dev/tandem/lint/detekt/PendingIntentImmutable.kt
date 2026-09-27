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
 * E00-28: every `PendingIntent`/`PendingIntentCompat` `getActivity(ies)/getBroadcast/getService/
 * getForegroundService` call, and every `TaskStackBuilder.getPendingIntent` call, must be
 * non-mutable and (where an `Intent` argument is visible at the call site) wrap an
 * explicit-component `Intent` (invariants 1, 4 — a mutable or implicit-target `PendingIntent` can
 * be redirected by another app to forge input into Tandem). A mutable `PendingIntent` is only
 * accepted when the enclosing function is listed in `tools/lint/pending-intent-mutable.allowlist`,
 * naming the issue that justifies it.
 *
 * A false positive here (a legitimately external implicit `Intent`, e.g. `ACTION_SEND` /
 * `Settings.ACTION_*`, or a `TaskStackBuilder` held in a `val` this rule can't see through) should
 * be resolved with a function-level `@Suppress("PendingIntentImmutable")` rather than weakening
 * the allowlist, since the allowlist is reserved for genuine `FLAG_MUTABLE`/`isMutable = true`
 * uses; detekt honors `@Suppress` with the rule ID on any enclosing declaration automatically.
 *
 * Syntactic limits (no type resolution available to a detekt rule; document per E00-28's "Android
 * Lint is heavier" note):
 *   - The Intent argument (or, for `getActivities`, each element of an inline `arrayOf(...)`) is
 *     recognized as explicit only when it is an inline `Intent(context, X::class.java)` (or
 *     `X::class`) constructor call, or an inline call chain ending in
 *     `.setClass(...)`/`.setComponent(...)`. An Intent built in a separate variable, a helper
 *     function, or a later statement is not tracked across statements and is reported as
 *     non-explicit.
 *   - `TaskStackBuilder.getPendingIntent(requestCode, flags)` is matched by callee name alone
 *     (there is no Intent argument at this call site to check at all — the stack's intents were
 *     added earlier via `addNextIntent*`, out of this rule's reach); only the mutability flag is
 *     checked for that shape.
 *   - The mutable-allowlist match is by containing file name + enclosing function simple name
 *     (no fully-qualified-name resolution), so a name collision across files is possible; that is
 *     an easy thing to catch in code review of the allowlist diff.
 */
class PendingIntentImmutable(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "PendingIntentImmutable",
            severity = Severity.Defect,
            description = "PendingIntent get*() calls must be non-mutable and wrap an explicit-component Intent " +
                "(invariants 1, 4).",
            debt = Debt.TWENTY_MINS,
        )

    private val mutableAllowlist: Set<String> by lazy {
        readAllowlist(valueOrDefault(MUTABLE_ALLOWLIST_PROPERTY, DEFAULT_MUTABLE_ALLOWLIST))
    }

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        val dotExpression = expression.parent as? KtDotQualifiedExpression ?: return
        if (dotExpression.selectorExpression !== expression) return
        val receiver = dotExpression.receiverExpression.text.substringAfterLast('.')
        val callee = expression.calleeExpression?.text ?: return

        when {
            receiver == "PendingIntent" && callee in GET_METHODS ->
                checkFlagConstantCall(expression, callee)
            receiver == "PendingIntentCompat" && callee in GET_METHODS ->
                checkMutableBooleanCall(expression, callee)
            callee == "getPendingIntent" ->
                checkTaskStackBuilderCall(expression, callee)
        }
    }

    // PendingIntent.getActivity/getActivities/getBroadcast/getService/getForegroundService(
    //     context, requestCode, intent(s), flags)
    private fun checkFlagConstantCall(expression: KtCallExpression, callee: String) {
        val flagsText = expression.valueArguments.getOrNull(FLAGS_ARG_INDEX)?.getArgumentExpression()?.text.orEmpty()
        if (!flagsText.contains("FLAG_IMMUTABLE") && !(flagsText.contains("FLAG_MUTABLE") && isAllowlisted(expression))) {
            val reason =
                if (flagsText.contains("FLAG_MUTABLE")) {
                    " (FLAG_MUTABLE needs an entry in tools/lint/pending-intent-mutable.allowlist naming the issue)"
                } else {
                    ""
                }
            report(CodeSmell(issue, Entity.from(expression), "PendingIntent.$callee() must pass FLAG_IMMUTABLE$reason."))
        }
        checkIntentArgument(expression, "PendingIntent.$callee()", INTENT_ARG_INDEX)
    }

    // PendingIntentCompat.getActivity/getActivities/getBroadcast/getService/getForegroundService(
    //     context, requestCode, intent(s), flags, isMutable)
    private fun checkMutableBooleanCall(expression: KtCallExpression, callee: String) {
        val isMutableText = expression.valueArguments.getOrNull(COMPAT_IS_MUTABLE_ARG_INDEX)?.getArgumentExpression()?.text
        if (isMutableText != "false" && !(isMutableText == "true" && isAllowlisted(expression))) {
            val reason =
                if (isMutableText == "true") {
                    " (needs an entry in tools/lint/pending-intent-mutable.allowlist naming the issue)"
                } else {
                    ""
                }
            report(CodeSmell(issue, Entity.from(expression), "PendingIntentCompat.$callee() must pass isMutable = false$reason."))
        }
        checkIntentArgument(expression, "PendingIntentCompat.$callee()", INTENT_ARG_INDEX)
    }

    // <TaskStackBuilder instance>.getPendingIntent(requestCode, flags); no Intent argument is
    // visible at this call site (see class KDoc).
    private fun checkTaskStackBuilderCall(expression: KtCallExpression, callee: String) {
        val flagsText = expression.valueArguments.getOrNull(TASK_STACK_BUILDER_FLAGS_ARG_INDEX)?.getArgumentExpression()?.text.orEmpty()
        if (flagsText.contains("FLAG_IMMUTABLE")) return
        if (flagsText.contains("FLAG_MUTABLE") && isAllowlisted(expression)) return

        val reason =
            if (flagsText.contains("FLAG_MUTABLE")) {
                " (FLAG_MUTABLE needs an entry in tools/lint/pending-intent-mutable.allowlist naming the issue)"
            } else {
                ""
            }
        report(CodeSmell(issue, Entity.from(expression), "TaskStackBuilder.$callee() must pass FLAG_IMMUTABLE$reason."))
    }

    private fun checkIntentArgument(expression: KtCallExpression, calleeDescription: String, intentArgIndex: Int) {
        val intentArg = expression.valueArguments.getOrNull(intentArgIndex)?.getArgumentExpression() ?: return
        if (isExplicitComponentIntent(intentArg)) return

        report(
            CodeSmell(
                issue,
                Entity.from(expression),
                "$calleeDescription must wrap an explicit-component Intent " +
                    "(Intent(context, X::class.java), or a chain ending in .setClass/.setComponent).",
            ),
        )
    }

    private fun isAllowlisted(expression: KtCallExpression): Boolean {
        val function = expression.getParentOfType<KtNamedFunction>(strict = true) ?: return false
        val name = function.name ?: return false
        // `containingFile.name` is the bare file name in the detekt-test harness (KtTestCompiler
        // always compiles as "Test.kt"), but a real Gradle `detekt` run backs it with the file's
        // full path; File(...).name normalizes both to match the allowlist's plain filename form.
        return "${File(expression.containingFile.name).name}#$name" in mutableAllowlist
    }

    private fun isExplicitComponentIntent(expression: KtExpression): Boolean {
        if (expression is KtCallExpression && expression.calleeExpression?.text in ARRAY_FACTORY_NAMES) {
            val elements = expression.valueArguments.mapNotNull { it.getArgumentExpression() }
            return elements.isNotEmpty() && elements.all(::isExplicitComponentIntent)
        }

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
        val GET_METHODS = setOf("getActivity", "getActivities", "getBroadcast", "getService", "getForegroundService")
        val ARRAY_FACTORY_NAMES = setOf("arrayOf")
        const val INTENT_ARG_INDEX = 2
        const val FLAGS_ARG_INDEX = 3
        const val COMPAT_IS_MUTABLE_ARG_INDEX = 4
        const val TASK_STACK_BUILDER_FLAGS_ARG_INDEX = 1
    }
}
