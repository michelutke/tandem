package dev.tandem.app

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

// Framework-free JUnit5 Jupiter test, proving `:app:testDebugUnitTest` runs Jupiter and
// Robolectric's JUnit4/Vintage tests (RobolectricSampleTest, SampleComposeUiTest) in the same
// report (E00-20 acceptance).
class SampleJupiterTest {
    @Test
    fun jupiterSample_additionOfOneAndTwo_equalsThree() {
        assertEquals(3, 1 + 2)
    }
}
