package dev.tandem.app.onboarding

/**
 * View model for the battery-optimization onboarding screen (E20-04, F-4.1, UC-02).
 *
 * Framework-free: reads [batteryOptimizationSource] and [deviceManufacturerSource] instead of
 * `PowerManager`/`Build.MANUFACTURER` directly, so it stays plain `unit:` tested against fakes
 * (CLAUDE.md's Robolectric rule).
 */
class BatteryOnboardingViewModel(
    private val batteryOptimizationSource: BatteryOptimizationSource,
    private val deviceManufacturerSource: DeviceManufacturerSource,
) {
    /** False once the app already ignores battery optimizations -- the caller skips the screen. */
    fun shouldShowScreen(): Boolean = !batteryOptimizationSource.isIgnoringBatteryOptimizations()

    /** The OEM guidance entry for this device's manufacturer. */
    fun oemGuidance(): OemGuidanceEntry = OemGuidance.forManufacturer(deviceManufacturerSource.manufacturer())

    /** This device's manufacturer, for the OEM section heading ("Extra steps for &lt;Manufacturer&gt;"). */
    fun manufacturer(): String = deviceManufacturerSource.manufacturer()
}
