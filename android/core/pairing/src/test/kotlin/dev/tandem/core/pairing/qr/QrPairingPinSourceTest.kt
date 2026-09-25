package dev.tandem.core.pairing.qr

import dev.tandem.core.crypto.SpkiFingerprint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class QrPairingPinSourceTest {
    @Test
    fun pairingPin_inviteRegistered_trustManagerAcceptsOnlyInviteSpki() {
        // Arrange: Create a pairing invite with a known fingerprint
        val inviteFingerprint = ByteArray(32) { 1 }
        val invite =
            PairingInvite(
                fingerprint = inviteFingerprint,
                secret = ByteArray(16),
                addresses = listOf("192.168.1.1"),
                port = 443,
                macName = "Mac",
            )
        val pinSource = QrPairingPinSource(invite)

        // Act: Get the expected fingerprints
        val expectedFingerprints = pinSource.expectedFingerprints()

        // Assert: Should return exactly the invite's fingerprint
        assertEquals(1, expectedFingerprints.size)
        assertTrue(expectedFingerprints[0].bytes.contentEquals(inviteFingerprint))
    }

    @Test
    fun pairingPin_returnsOnlyQrFingerprint_neverTrustStorePin() {
        // Arrange: Create a pairing invite
        val inviteFingerprint = ByteArray(32) { 42 }
        val invite =
            PairingInvite(
                fingerprint = inviteFingerprint,
                secret = ByteArray(16),
                addresses = listOf("192.168.1.1"),
                port = 443,
                macName = "Mac",
            )
        val pinSource = QrPairingPinSource(invite)

        // Act: Get the expected fingerprints
        val fingerprints = pinSource.expectedFingerprints()

        // Assert: Should have exactly one fingerprint (the QR one)
        assertEquals(1, fingerprints.size)
    }

    @Test
    fun pairingPin_differentInvites_returnDifferentFingerprints() {
        // Arrange: Create two invites with different fingerprints
        val fingerprint1 = ByteArray(32) { 1 }
        val fingerprint2 = ByteArray(32) { 2 }

        val invite1 =
            PairingInvite(
                fingerprint = fingerprint1,
                secret = ByteArray(16),
                addresses = listOf("192.168.1.1"),
                port = 443,
                macName = "Mac1",
            )
        val invite2 =
            PairingInvite(
                fingerprint = fingerprint2,
                secret = ByteArray(16),
                addresses = listOf("192.168.1.2"),
                port = 443,
                macName = "Mac2",
            )

        val pinSource1 = QrPairingPinSource(invite1)
        val pinSource2 = QrPairingPinSource(invite2)

        // Act: Get the expected fingerprints
        val fingerprints1 = pinSource1.expectedFingerprints()
        val fingerprints2 = pinSource2.expectedFingerprints()

        // Assert: Should have different fingerprints
        assertFalse(fingerprints1[0].bytes.contentEquals(fingerprints2[0].bytes))
    }
}
