package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.RuleSet
import io.gitlab.arturbosch.detekt.api.RuleSetProvider

/** Tandem's custom detekt rule set. Empty until E00-14 / E00-18 add their rules. */
class TandemRuleSetProvider : RuleSetProvider {
    override val ruleSetId: String = "tandem"

    override fun instance(config: Config): RuleSet = RuleSet(ruleSetId, emptyList())
}
