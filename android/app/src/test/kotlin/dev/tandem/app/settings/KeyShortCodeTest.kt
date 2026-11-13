package dev.tandem.app.settings

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.util.Base64

class KeyShortCodeTest {
    private fun base64Url(bytes: ByteArray) = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    @Test
    fun keyShortCode_fingerprint_isFirstEightBytesAsFourHexGroups() {
        val fingerprint = ByteArray(32) { (it + 0x7F).toByte() }.also { it[1] = 0x3A.toByte() }

        assertEquals("7F3A 8182 8384 8586", keyShortCode(base64Url(fingerprint)))
    }

    @Test
    fun keyShortCode_lowBytes_arePaddedToTwoHexDigits() {
        assertEquals("0001 0203 0405 0607", keyShortCode(base64Url(ByteArray(32) { it.toByte() })))
    }
}
