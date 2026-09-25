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

/**
 * E10-14: only `core/crypto` may touch `AndroidKeyStore` or compute HMAC-SHA256 directly (module
 * boundary check; invariants 3, 6). `core/crypto` itself is excluded from this rule via
 * `detekt.yml`, mirroring `SocketOnlyInTransport` (E00-14).
 *
 * Flags `KeyStore.getInstance("AndroidKeyStore")` and `Mac.getInstance("HmacSHA256")` call sites;
 * these are the exact banned symbols named in the backlog description, not every `KeyStore`/`Mac`
 * provider (e.g. a `BKS`/`PKCS12` trust-store `KeyStore` elsewhere is untouched by this rule).
 */
class KeyMaterialOnlyInCrypto(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "KeyMaterialOnlyInCrypto",
            severity = Severity.Defect,
            description = "Only core/crypto may reference AndroidKeyStore or compute HMAC-SHA256 directly (E10-14).",
            debt = Debt.TWENTY_MINS,
        )

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        if (expression.calleeExpression?.text != "getInstance") return
        val dotExpression = expression.parent as? KtDotQualifiedExpression ?: return
        if (dotExpression.selectorExpression !== expression) return
        val receiver = dotExpression.receiverExpression.text.substringAfterLast('.')
        val firstArgText = expression.valueArguments.firstOrNull()?.getArgumentExpression()?.text.orEmpty()

        when {
            receiver == "KeyStore" && firstArgText.contains(ANDROID_KEY_STORE_PROVIDER) ->
                report(
                    CodeSmell(
                        issue,
                        Entity.from(expression),
                        "`KeyStore.getInstance(\"$ANDROID_KEY_STORE_PROVIDER\")` bypasses the core/crypto " +
                            "key-material boundary (E10-14).",
                    ),
                )
            receiver == "Mac" && firstArgText.contains(HMAC_SHA256_ALGORITHM) ->
                report(
                    CodeSmell(
                        issue,
                        Entity.from(expression),
                        "`Mac.getInstance(\"$HMAC_SHA256_ALGORITHM\")` bypasses the core/crypto " +
                            "key-material boundary (E10-14).",
                    ),
                )
        }
    }

    private companion object {
        const val ANDROID_KEY_STORE_PROVIDER = "AndroidKeyStore"
        const val HMAC_SHA256_ALGORITHM = "HmacSHA256"
    }
}
