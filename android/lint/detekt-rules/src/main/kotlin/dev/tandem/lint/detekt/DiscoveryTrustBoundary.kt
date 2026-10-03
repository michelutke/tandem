package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.CodeSmell
import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.Debt
import io.gitlab.arturbosch.detekt.api.Entity
import io.gitlab.arturbosch.detekt.api.Issue
import io.gitlab.arturbosch.detekt.api.Rule
import io.gitlab.arturbosch.detekt.api.Severity
import org.jetbrains.kotlin.psi.KtDotQualifiedExpression
import org.jetbrains.kotlin.psi.KtImportDirective
import org.jetbrains.kotlin.psi.KtUserType
import org.jetbrains.kotlin.psi.psiUtil.getParentOfType

/**
 * E21-06: discovery is a hint, never a trust decision (invariants 1, 3). The discovery module may
 * only produce candidate addresses; it must not reference the trust store or the pin verifier, so
 * a discovery match can never mark a peer trusted or skip the handshake's SPKI pin check.
 * Applied to `core/discovery` only via `detekt.yml`.
 */
class DiscoveryTrustBoundary(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "DiscoveryTrustBoundary",
            severity = Severity.Defect,
            description = "core/discovery must not reference the trust store (core.storage.trust) or the pin " +
                "verifier (PinningTrustManager, PinSource); discovery is a hint only (E21-06).",
            debt = Debt.TWENTY_MINS,
        )

    override fun visitImportDirective(importDirective: KtImportDirective) {
        super.visitImportDirective(importDirective)
        val fqName = importDirective.importedFqName?.asString() ?: return
        if (isBanned(fqName)) reportBanned(Entity.from(importDirective), fqName)
    }

    override fun visitDotQualifiedExpression(expression: KtDotQualifiedExpression) {
        super.visitDotQualifiedExpression(expression)
        if (expression.getParentOfType<KtImportDirective>(strict = true) != null) return
        if (isBanned(expression.text)) reportBanned(Entity.from(expression), expression.text)
    }

    override fun visitUserType(type: KtUserType) {
        super.visitUserType(type)
        if (type.getParentOfType<KtImportDirective>(strict = true) != null) return
        if (isBanned(type.text)) reportBanned(Entity.from(type), type.text)
    }

    private fun isBanned(name: String): Boolean = BANNED_PREFIXES.any { name.startsWith(it) }

    private fun reportBanned(
        entity: Entity,
        name: String,
    ) = report(CodeSmell(issue, entity, "`$name` lets discovery touch trust or verification (E21-06)."))

    private companion object {
        val BANNED_PREFIXES =
            listOf(
                "dev.tandem.core.storage.trust.",
                "dev.tandem.core.crypto.PinningTrustManager",
                "dev.tandem.core.crypto.PinSource",
            )
    }
}
