package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.RuleSet
import io.gitlab.arturbosch.detekt.api.RuleSetProvider

/** Tandem custom detekt rules: InjectedClockOnly (E00-18); SocketOnlyInTransport (E00-14). */
class TandemRuleSetProvider : RuleSetProvider {
    override val ruleSetId: String = "tandem"

    override fun instance(config: Config): RuleSet =
        RuleSet(ruleSetId, listOf(InjectedClockOnly(config), SocketOnlyInTransport(config)))
}
