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
import org.jetbrains.kotlin.psi.psiUtil.getParentOfType

/**
 * E00-14: only `core/transport` opens raw sockets. Every other module is excluded from touching
 * `java.net.Socket`, `javax.net.ssl.SSLSocket` or `java.nio.channels.SocketChannel`; `core/transport`
 * itself is excluded from this rule via `detekt.yml`.
 */
class SocketOnlyInTransport(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "SocketOnlyInTransport",
            severity = Severity.Defect,
            description = "Only core/transport may open raw sockets (java.net.Socket, javax.net.ssl.SSLSocket, " +
                "java.nio.channels.SocketChannel).",
            debt = Debt.TWENTY_MINS,
        )

    override fun visitImportDirective(importDirective: KtImportDirective) {
        super.visitImportDirective(importDirective)
        val fqName = importDirective.importedFqName?.asString() ?: return
        if (fqName in BANNED_FQ_NAMES) {
            report(CodeSmell(issue, Entity.from(importDirective), "`$fqName` bypasses the transport-only socket seam (E00-14)."))
        }
    }

    override fun visitDotQualifiedExpression(expression: KtDotQualifiedExpression) {
        super.visitDotQualifiedExpression(expression)
        if (expression.getParentOfType<KtImportDirective>(strict = true) != null) return
        val text = expression.text
        val match = BANNED_FQ_NAMES.firstOrNull { text.startsWith(it) } ?: return
        report(CodeSmell(issue, Entity.from(expression), "`$match` bypasses the transport-only socket seam (E00-14)."))
    }

    private companion object {
        val BANNED_FQ_NAMES =
            setOf(
                "java.net.Socket",
                "javax.net.ssl.SSLSocket",
                "java.nio.channels.SocketChannel",
            )
    }
}
