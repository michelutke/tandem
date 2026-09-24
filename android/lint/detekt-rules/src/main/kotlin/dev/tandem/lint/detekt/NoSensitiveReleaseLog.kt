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
import org.jetbrains.kotlin.psi.KtNameReferenceExpression
import org.jetbrains.kotlin.psi.KtStringTemplateEntryWithExpression
import org.jetbrains.kotlin.psi.KtStringTemplateExpression
import java.io.File

/**
 * E00-17: `Log.*`/`Timber.*` calls must never reference a symbol from the shared
 * `tools/lint/sensitive-symbols.txt` (notification text, clipboard content, message bodies,
 * secrets, ...; invariant 7). The file is re-read from disk on every rule run (path configurable
 * via the `sensitiveSymbolsFile` detekt.yml property), so adding a symbol needs no code change.
 * Scoped to release-visible source sets via `excludes` in detekt.yml (`src/debug`, `src/test`,
 * `src/androidTest`).
 */
class NoSensitiveReleaseLog(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "NoSensitiveReleaseLog",
            severity = Severity.Defect,
            description = "Log/Timber call references a sensitive symbol from tools/lint/sensitive-symbols.txt (invariant 7).",
            debt = Debt.TEN_MINS,
        )

    private val sensitiveSymbols: Set<String> by lazy {
        readSymbols(valueOrDefault(SENSITIVE_SYMBOLS_FILE_PROPERTY, DEFAULT_SENSITIVE_SYMBOLS_FILE))
    }

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        val dotExpression = expression.parent as? KtDotQualifiedExpression ?: return
        if (dotExpression.selectorExpression !== expression) return
        val receiver = dotExpression.receiverExpression.text.substringAfterLast('.')
        if (receiver !in LOGGERS) return
        val callee = expression.calleeExpression?.text ?: return

        val hit =
            expression.valueArguments.firstNotNullOfOrNull { findSensitiveReference(it.getArgumentExpression()) }
        if (hit != null) {
            report(
                CodeSmell(
                    issue,
                    Entity.from(expression),
                    "`$receiver.$callee` logs `$hit`, which is listed in tools/lint/sensitive-symbols.txt (invariant 7).",
                ),
            )
        }
    }

    private fun findSensitiveReference(expression: KtExpression?): String? =
        when (expression) {
            null -> null
            is KtNameReferenceExpression -> expression.getReferencedName().takeIf { it in sensitiveSymbols }
            is KtStringTemplateExpression ->
                expression.entries
                    .filterIsInstance<KtStringTemplateEntryWithExpression>()
                    .firstNotNullOfOrNull { findSensitiveReference(it.expression) }
            // A qualified access derived from a sensitive symbol (e.g. `clipboardText.length`) is
            // treated as a redacted representation, not raw content.
            else -> null
        }

    private fun readSymbols(path: String): Set<String> {
        val configured = File(path)
        val file = if (configured.isAbsolute) configured else File(System.getProperty("user.dir"), path)
        if (!file.isFile) return emptySet()
        return file.readLines()
            .map(String::trim)
            .filterTo(LinkedHashSet()) { it.isNotEmpty() && !it.startsWith("#") }
    }

    private companion object {
        const val SENSITIVE_SYMBOLS_FILE_PROPERTY = "sensitiveSymbolsFile"
        const val DEFAULT_SENSITIVE_SYMBOLS_FILE = "../tools/lint/sensitive-symbols.txt"
        val LOGGERS = setOf("Log", "Timber")
    }
}
