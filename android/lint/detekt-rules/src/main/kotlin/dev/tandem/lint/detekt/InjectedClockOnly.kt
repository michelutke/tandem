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
 * E00-18: time and dispatchers are injected. Production code takes `java.time.Clock`, an
 * `ElapsedRealtimeSource` and injected dispatchers; it never reads the system clock, hard-codes
 * a dispatcher or schedules with `Handler.postDelayed`. DI modules and `core/testing` are excluded
 * via `detekt.yml`.
 */
class InjectedClockOnly(config: Config = Config.empty) : Rule(config) {
    override val issue =
        Issue(
            id = "InjectedClockOnly",
            severity = Severity.Defect,
            description = "Use an injected Clock / ElapsedRealtimeSource / dispatcher instead of system time.",
            debt = Debt.FIVE_MINS,
        )

    override fun visitDotQualifiedExpression(expression: KtDotQualifiedExpression) {
        super.visitDotQualifiedExpression(expression)
        val receiver = expression.receiverExpression.text.substringAfterLast('.')
        val selector = expression.selectorExpression
        val call = selector as? KtCallExpression
        val name = call?.calleeExpression?.text ?: selector?.text ?: return
        val key = "$receiver.$name"
        val takesClock = call != null && call.valueArguments.isNotEmpty() && key in NOW_WITH_CLOCK_ALLOWED
        if (key in BANNED && !takesClock) {
            report(CodeSmell(issue, Entity.from(expression), "`$key` bypasses the injected time seam (E00-18)."))
        }
    }

    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        if (expression.calleeExpression?.text == "postDelayed") {
            report(CodeSmell(issue, Entity.from(expression), "Schedule with `delay` in an injected scope, not postDelayed (E00-18)."))
        }
    }

    private companion object {
        val NOW_WITH_CLOCK_ALLOWED =
            setOf("Instant.now", "LocalDate.now", "LocalDateTime.now", "ZonedDateTime.now", "OffsetDateTime.now")
        val BANNED =
            NOW_WITH_CLOCK_ALLOWED +
                setOf(
                    "System.currentTimeMillis",
                    "System.nanoTime",
                    "SystemClock.elapsedRealtime",
                    "SystemClock.uptimeMillis",
                    "Clock.systemUTC",
                    "Clock.systemDefaultZone",
                    "Dispatchers.IO",
                    "Dispatchers.Default",
                )
    }
}
