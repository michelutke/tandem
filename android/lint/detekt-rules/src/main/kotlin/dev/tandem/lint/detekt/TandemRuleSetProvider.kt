package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.RuleSet
import io.gitlab.arturbosch.detekt.api.RuleSetProvider

/**
 * Tandem custom detekt rules: InjectedClockOnly (E00-18), SocketOnlyInTransport (E00-14),
 * NoSensitiveReleaseLog (E00-17), PendingIntentImmutable, ImplicitInternalIntent,
 * TandemActivityBase (E00-28) and NoListenerSockets (invariant 4, E12-04).
 * NoSensitiveReleaseLog (E00-17), PendingIntentImmutable, ImplicitInternalIntent and
 * TandemActivityBase (E00-28), KeyMaterialOnlyInCrypto (E10-14).
 */
class TandemRuleSetProvider : RuleSetProvider {
    override val ruleSetId: String = "tandem"

    override fun instance(config: Config): RuleSet =
        RuleSet(
            ruleSetId,
            listOf(
                InjectedClockOnly(config),
                SocketOnlyInTransport(config),
                NoSensitiveReleaseLog(config),
                PendingIntentImmutable(config),
                ImplicitInternalIntent(config),
                TandemActivityBase(config),
                NoListenerSockets(config),
                KeyMaterialOnlyInCrypto(config),
            ),
        )
}
