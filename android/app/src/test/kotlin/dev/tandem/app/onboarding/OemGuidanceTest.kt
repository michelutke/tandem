package dev.tandem.app.onboarding

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// E20-04 tdd:
//   unit: oemGuidance_manufacturerXiaomi_returnsXiaomiEntry
//   unit: oemGuidance_unknownManufacturer_returnsGenericEntry
class OemGuidanceTest {
    @Test
    fun oemGuidance_manufacturerSamsung_returnsSamsungEntry() {
        assertEquals(OemGuidance.SAMSUNG, OemGuidance.forManufacturer("Samsung"))
    }

    @Test
    fun oemGuidance_manufacturerXiaomi_returnsXiaomiEntry() {
        assertEquals(OemGuidance.XIAOMI, OemGuidance.forManufacturer("Xiaomi"))
    }

    @Test
    fun oemGuidance_manufacturerOnePlus_returnsOnePlusEntry() {
        assertEquals(OemGuidance.ONEPLUS, OemGuidance.forManufacturer("OnePlus"))
    }

    @Test
    fun oemGuidance_manufacturerHuawei_returnsHuaweiEntry() {
        assertEquals(OemGuidance.HUAWEI, OemGuidance.forManufacturer("Huawei"))
    }

    @Test
    fun oemGuidance_manufacturerMixedCase_stillMatchesEntry() {
        assertEquals(OemGuidance.XIAOMI, OemGuidance.forManufacturer("xiaomi"))
    }

    @Test
    fun oemGuidance_unknownManufacturer_returnsGenericEntry() {
        assertEquals(OemGuidance.GENERIC, OemGuidance.forManufacturer("Google"))
    }
}
