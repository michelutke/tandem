package dev.tandem.feature.messaging

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

// E50-04 tdd: smsSender_twoHundredCharGsm7Body_dividedIntoTwoParts,
// smsSender_hundredCharUcs2Body_dividedIntoTwoParts. Robolectric 4.17 has no ISms service, so the
// real `SmsManager.divideMessage` only runs on a device or emulator.
@RunWith(AndroidJUnit4::class)
class SmsManagerSenderInstrumentedTest {
    private val sender = SmsManagerSender(InstrumentationRegistry.getInstrumentation().targetContext)

    @Test
    fun smsSender_twoHundredCharGsm7Body_dividedIntoTwoParts() {
        assertEquals(2, sender.divide("a".repeat(200)).size)
    }

    @Test
    fun smsSender_hundredCharUcs2Body_dividedIntoTwoParts() {
        val parts = sender.divide("é中".repeat(50))

        assertEquals(2, parts.size)
        assertEquals(67, parts.first().length)
    }
}
