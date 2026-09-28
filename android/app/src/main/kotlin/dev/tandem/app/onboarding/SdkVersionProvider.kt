package dev.tandem.app.onboarding

import android.os.Build

/**
 * Seam over `Build.VERSION.SDK_INT` (E20-14): which Android version [OnboardingViewModel] should
 * plan the onboarding sequence for, so it stays plain unit-tested against a fake instead of
 * touching the framework directly (CLAUDE.md's Robolectric rule; same idiom as this package's
 * `DeviceManufacturerSource`). [SystemSdkVersionProvider] is the only production implementation.
 */
fun interface SdkVersionProvider {
    fun sdkInt(): Int
}

/** Production implementation backed by the real `Build.VERSION.SDK_INT`. */
object SystemSdkVersionProvider : SdkVersionProvider {
    override fun sdkInt(): Int = Build.VERSION.SDK_INT
}
