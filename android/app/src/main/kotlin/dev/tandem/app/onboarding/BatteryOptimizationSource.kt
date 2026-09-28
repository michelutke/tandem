package dev.tandem.app.onboarding

import android.content.Context
import android.os.PowerManager

/**
 * Seam over `PowerManager.isIgnoringBatteryOptimizations` (E20-04, F-4.1): whether this app is
 * already exempt from battery optimization, so [BatteryOnboardingViewModel] stays plain
 * unit-tested against a fake instead of touching the framework directly (CLAUDE.md's Robolectric
 * rule; same idiom as `core/discovery`'s `NsdSource`). [SystemBatteryOptimizationSource] is the
 * only production implementation.
 */
fun interface BatteryOptimizationSource {
    fun isIgnoringBatteryOptimizations(): Boolean
}

/** Production implementation backed by the real `PowerManager`. */
class SystemBatteryOptimizationSource(
    private val context: Context,
) : BatteryOptimizationSource {
    override fun isIgnoringBatteryOptimizations(): Boolean =
        context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
}
