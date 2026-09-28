package dev.tandem.app.onboarding

/** Test fake (E20-04 tdd) standing in for [BatteryOptimizationSource] against real `PowerManager`. */
class FakeBatteryOptimizationSource(
    private val ignoringBatteryOptimizations: Boolean,
) : BatteryOptimizationSource {
    override fun isIgnoringBatteryOptimizations(): Boolean = ignoringBatteryOptimizations
}
