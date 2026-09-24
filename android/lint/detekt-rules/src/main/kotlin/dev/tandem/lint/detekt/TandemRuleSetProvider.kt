package dev.tandem.lint.detekt

import io.gitlab.arturbosch.detekt.api.Config
import io.gitlab.arturbosch.detekt.api.RuleSet
import io.gitlab.arturbosch.detekt.api.RuleSetProvider

/**
 * Tandem custom detekt rules: InjectedClockOnly (E00-18), NoSensitiveReleaseLog (E00-17);
 * module-dependency rules follow in E00-14.
 */
class TandemRuleSetProvider : RuleSetProvider {
    override val ruleSetId: String = "tandem"

    override fun instance(config: Config): RuleSet =
        RuleSet(ruleSetId, listOf(InjectedClockOnly(config), NoSensitiveReleaseLog(config)))
}
