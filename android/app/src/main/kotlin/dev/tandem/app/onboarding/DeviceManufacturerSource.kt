package dev.tandem.app.onboarding

import android.os.Build

/**
 * Seam over `Build.MANUFACTURER` (E20-04, F-4.1): which OEM guidance section
 * [BatteryOnboardingViewModel] should show, so it stays plain unit-tested against a fake instead
 * of touching the framework directly (CLAUDE.md's Robolectric rule; same idiom as
 * `core/pairing`'s `DeviceInfoProvider`). [SystemDeviceManufacturerSource] is the only production
 * implementation.
 */
fun interface DeviceManufacturerSource {
    fun manufacturer(): String
}

/** Production implementation backed by the real `Build.MANUFACTURER` only. */
object SystemDeviceManufacturerSource : DeviceManufacturerSource {
    override fun manufacturer(): String = Build.MANUFACTURER
}
