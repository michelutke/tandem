package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PENDING_MAX_AGE_MS
import dev.tandem.core.storage.trust.PeerRecord
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class PairedFingerprintsTest {
    private val primary = SpkiFingerprint(ByteArray(32) { 1 })
    private val grace = SpkiFingerprint(ByteArray(32) { 2 })
    private val pending = SpkiFingerprint(ByteArray(32) { 3 })
    private val now = 10_000_000_000L

    private fun record(
        graceExpiresAt: Long? = null,
        pendingSince: Long? = null,
    ) = PeerRecord(
        deviceId = "mac",
        displayName = "Mac",
        spkiSha256Base64Url = primary.base64Url,
        pairedAtEpochMs = 0,
        lastSeenEpochMs = 0,
        capabilities = emptyList(),
        graceSpkiSha256Base64Url = graceExpiresAt?.let { grace.base64Url },
        graceExpiresAtEpochMs = graceExpiresAt,
        pendingSpkiSha256Base64Url = pendingSince?.let { pending.base64Url },
        pendingSinceEpochMs = pendingSince,
    )

    @Test
    fun acceptedPins_noRotation_onlyPrimary() {
        assertEquals(listOf(primary.base64Url), record().acceptedPins(now).map { it.base64Url })
    }

    @Test
    fun acceptedPins_unexpiredGraceAndPending_allThreeAccepted() {
        val pins = record(graceExpiresAt = now + 1, pendingSince = now - 1).acceptedPins(now).map { it.base64Url }

        assertEquals(listOf(primary, grace, pending).map { it.base64Url }, pins)
    }

    @Test
    fun acceptedPins_expiredGrace_graceDropped() {
        assertEquals(listOf(primary.base64Url), record(graceExpiresAt = now).acceptedPins(now).map { it.base64Url })
    }

    @Test
    fun acceptedPins_pendingOlderThanMaxAge_pendingDropped() {
        val pins = record(pendingSince = now - PENDING_MAX_AGE_MS).acceptedPins(now).map { it.base64Url }

        assertEquals(listOf(primary.base64Url), pins)
    }
}
