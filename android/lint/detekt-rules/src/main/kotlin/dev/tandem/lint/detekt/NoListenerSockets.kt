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
import org.jetbrains.kotlin.psi.KtImportDirective
import org.jetbrains.kotlin.psi.psiUtil.getParentOfType

/**
 * Invariant 4: the Android app opens no listening sockets, anywhere — unlike `SocketOnlyInTransport`
 * (E00-14), this rule has no module exclusion, since nothing in this app may listen, not even
 * `core/transport`. Only test sources are excluded (`detekt.yml`), since the E12-04 JVM test-only
 * TLS server legitimately binds a `SSLServerSocket` to exercise the client against a real peer.
 */
class NoListenerSockets(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "NoListenerSockets",
            severity = Severity.Defect,
            description = "No main-source code may open a listening socket (java.net.ServerSocket, " +
                "javax.net.ssl.SSLServerSocket, java.nio.channels.ServerSocketChannel, and related " +
                "server-socket/listener APIs) — invariant 4.",
            debt = Debt.TWENTY_MINS,
        )

    override fun visitImportDirective(importDirective: KtImportDirective) {
        super.visitImportDirective(importDirective)
        val fqName = importDirective.importedFqName?.asString() ?: return
        if (fqName in BANNED_FQ_NAMES) {
            report(CodeSmell(issue, Entity.from(importDirective), "`$fqName` opens a listening socket (invariant 4)."))
        }
    }

    override fun visitDotQualifiedExpression(expression: KtDotQualifiedExpression) {
        super.visitDotQualifiedExpression(expression)
        if (expression.getParentOfType<KtImportDirective>(strict = true) != null) return

        val text = expression.text
        val fqMatch = BANNED_FQ_NAMES.firstOrNull { text.startsWith(it) }
        if (fqMatch != null) {
            report(CodeSmell(issue, Entity.from(expression), "`$fqMatch` opens a listening socket (invariant 4)."))
            return
        }

        val memberName = selectorMemberName(expression) ?: return
        if (memberName in BANNED_MEMBER_NAMES) {
            report(CodeSmell(issue, Entity.from(expression), "`$memberName` opens a listening socket (invariant 4)."))
        }
    }

    private fun selectorMemberName(expression: KtDotQualifiedExpression): String? =
        when (val selector = expression.selectorExpression) {
            is KtCallExpression -> selector.calleeExpression?.text
            else -> selector?.text
        }

    private companion object {
        val BANNED_FQ_NAMES =
            setOf(
                "java.net.ServerSocket",
                "javax.net.ssl.SSLServerSocket",
                "java.nio.channels.ServerSocketChannel",
                "javax.net.ServerSocketFactory",
                "javax.net.ssl.SSLServerSocketFactory",
                "java.nio.channels.AsynchronousServerSocketChannel",
                "android.net.LocalServerSocket",
                "java.net.DatagramSocket",
                "java.nio.channels.DatagramChannel",
            )

        /**
         * Member names matched regardless of the (often inferred) receiver type, so e.g.
         * `SSLContext.getInstance("TLS").serverSocketFactory.createServerSocket(0)` is caught even
         * though `serverSocketFactory`'s static type is never spelled out at the call site.
         */
        val BANNED_MEMBER_NAMES =
            setOf(
                "createServerSocket",
                "openServerSocketChannel",
                "serverSocketFactory",
                "registerService",
            )
    }
}
