package dev.tandem.app.onboarding

/** Test fake (E20-04 tdd) standing in for [DeviceManufacturerSource] against real `Build.MANUFACTURER`. */
class FakeDeviceManufacturerSource(
    private val manufacturer: String,
) : DeviceManufacturerSource {
    override fun manufacturer(): String = manufacturer
}
