package dev.tandem.app.onboarding

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// E20-04 tdd: unit: batteryOnboardingViewModel_alreadyIgnoringOptimizations_skipsScreen
class BatteryOnboardingViewModelTest {
    @Test
    fun batteryOnboardingViewModel_alreadyIgnoringOptimizations_skipsScreen() {
        val viewModel =
            BatteryOnboardingViewModel(
                batteryOptimizationSource = FakeBatteryOptimizationSource(ignoringBatteryOptimizations = true),
                deviceManufacturerSource = FakeDeviceManufacturerSource(manufacturer = "Google"),
            )

        assertEquals(false, viewModel.shouldShowScreen())
    }

    @Test
    fun batteryOnboardingViewModel_notIgnoringOptimizations_showsScreen() {
        val viewModel =
            BatteryOnboardingViewModel(
                batteryOptimizationSource = FakeBatteryOptimizationSource(ignoringBatteryOptimizations = false),
                deviceManufacturerSource = FakeDeviceManufacturerSource(manufacturer = "Google"),
            )

        assertEquals(true, viewModel.shouldShowScreen())
    }

    @Test
    fun batteryOnboardingViewModel_manufacturerXiaomi_oemGuidanceReturnsXiaomiEntry() {
        val viewModel =
            BatteryOnboardingViewModel(
                batteryOptimizationSource = FakeBatteryOptimizationSource(ignoringBatteryOptimizations = false),
                deviceManufacturerSource = FakeDeviceManufacturerSource(manufacturer = "Xiaomi"),
            )

        assertEquals(OemGuidance.XIAOMI, viewModel.oemGuidance())
    }
}
