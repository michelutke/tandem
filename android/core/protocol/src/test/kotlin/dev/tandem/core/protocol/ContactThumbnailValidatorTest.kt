package dev.tandem.core.protocol

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * ContactThumbnailValidator tests (E51-01): the CONTACTS channel's `photo_thumbnail` byte cap
 * (docs/protocol/SPEC.md #contacts-channel "Thumbnail cap"), 32,768 bytes (32 KiB).
 */
class ContactThumbnailValidatorTest {
    @Test
    fun contactThumbnailValidator_emptyThumbnail_isValid() {
        assertTrue(ContactThumbnailValidator.isValid(ByteArray(0)))
    }

    @Test
    fun contactThumbnailValidator_exactly32768Bytes_isValid() {
        val thumbnail = ByteArray(ContactThumbnailValidator.MAX_PHOTO_THUMBNAIL_BYTES)
        assertTrue(ContactThumbnailValidator.isValid(thumbnail))
    }

    @Test
    fun contactThumbnailValidator_oneByteOver32768_isRejected() {
        val thumbnail = ByteArray(ContactThumbnailValidator.MAX_PHOTO_THUMBNAIL_BYTES + 1)
        assertFalse(ContactThumbnailValidator.isValid(thumbnail))
    }

    @Test
    fun contactThumbnailValidator_wellOverCap_isRejected() {
        val thumbnail = ByteArray(1_000_000)
        assertFalse(ContactThumbnailValidator.isValid(thumbnail))
    }
}
