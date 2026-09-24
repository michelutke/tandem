package dev.tandem.core.crypto

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ConstantTimeCompareTest {
    @Test
    fun constantTimeEquals_equalArrays_returnsTrue() {
        val a = byteArrayOf(1, 2, 3, 4, 5)
        val b = byteArrayOf(1, 2, 3, 4, 5)

        assertTrue(constantTimeEquals(a, b))
    }

    @Test
    fun constantTimeEquals_mismatchAtFirstByte_returnsFalseAfterFullScan() {
        val a = byteArrayOf(9, 2, 3, 4, 5)
        val b = byteArrayOf(1, 2, 3, 4, 5)
        val counter = ByteAccessCounter()

        val result = constantTimeEquals(a, b, counter)

        assertFalse(result)
        assertEquals(2 * a.size, counter.accessCount)
    }

    @Test
    fun constantTimeEquals_mismatchAtLastByte_sameAccessCountAsFirstByte() {
        val firstByteMismatchCounter = ByteAccessCounter()
        constantTimeEquals(byteArrayOf(9, 2, 3, 4, 5), byteArrayOf(1, 2, 3, 4, 5), firstByteMismatchCounter)

        val lastByteMismatchCounter = ByteAccessCounter()
        constantTimeEquals(byteArrayOf(1, 2, 3, 4, 9), byteArrayOf(1, 2, 3, 4, 5), lastByteMismatchCounter)

        assertEquals(firstByteMismatchCounter.accessCount, lastByteMismatchCounter.accessCount)
    }

    @Test
    fun constantTimeEquals_differentLengths_returnsFalseWithoutThrowing() {
        val a = byteArrayOf(1, 2, 3)
        val b = byteArrayOf(1, 2, 3, 4)

        assertFalse(constantTimeEquals(a, b))
    }
}
