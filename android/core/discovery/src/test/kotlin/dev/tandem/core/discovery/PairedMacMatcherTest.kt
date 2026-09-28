package dev.tandem.core.discovery

import dev.tandem.core.crypto.DiscoveryRotatingId
import dev.tandem.core.crypto.SpkiFingerprint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset

/**
 * [PairedMacMatcher] tests (E21-05; issue "Recognize paired Macs from rotating id"'s `tdd:` list).
 * A match is a connection-candidate hint only (invariant 3) -- these tests assert only whether
 * [PairedMacMatcher.match] finds a fingerprint whose rotating id is within the +/-1 day skew
 * window, never that a match authenticates anything.
 */
class PairedMacMatcherTest {
    private val now = Instant.parse("2025-06-15T12:00:00Z")
    private val pairedFingerprint = SpkiFingerprint(ByteArray(32) { it.toByte() })
    private val otherFingerprint = SpkiFingerprint(ByteArray(32) { (it + 1).toByte() })

    private fun matcherAt(
        instant: Instant,
        zone: ZoneOffset = ZoneOffset.UTC,
    ) = PairedMacMatcher(Clock.fixed(instant, zone))

    private fun serviceAdvertising(
        idHex: String,
        v: String = "1",
    ) = ResolvedService(
        serviceName = "mac-1",
        host = "192.168.1.5",
        port = 5353,
        txtRecords = mapOf("v" to v, "id" to idHex),
    )

    private fun idHexForDayOffset(
        fingerprint: SpkiFingerprint,
        instant: Instant,
        offset: Long,
    ): String {
        val dayIndex = DiscoveryRotatingId.dayIndex(instant.epochSecond) + offset
        return DiscoveryRotatingId.computeHex(fingerprint.bytes, dayIndex)
    }

    @Test
    fun pairedMacMatcher_idForDayMinus1_matched() {
        val idHex = idHexForDayOffset(pairedFingerprint, now, -1)
        val matcher = matcherAt(now)

        val match = matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNotNull(match)
        assertEquals(pairedFingerprint.base64Url, match!!.fingerprint.base64Url)
    }

    @Test
    fun pairedMacMatcher_idForDay0_matched() {
        val idHex = idHexForDayOffset(pairedFingerprint, now, 0)
        val matcher = matcherAt(now)

        val match = matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNotNull(match)
        assertEquals(pairedFingerprint.base64Url, match!!.fingerprint.base64Url)
    }

    @Test
    fun pairedMacMatcher_idForDayPlus1_matched() {
        val idHex = idHexForDayOffset(pairedFingerprint, now, 1)
        val matcher = matcherAt(now)

        val match = matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNotNull(match)
        assertEquals(pairedFingerprint.base64Url, match!!.fingerprint.base64Url)
    }

    @Test
    fun pairedMacMatcher_idForDayMinus2_notMatched() {
        val idHex = idHexForDayOffset(pairedFingerprint, now, -2)
        val matcher = matcherAt(now)

        val match = matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNull(match)
    }

    @Test
    fun pairedMacMatcher_idForDayPlus2_notMatched() {
        val idHex = idHexForDayOffset(pairedFingerprint, now, 2)
        val matcher = matcherAt(now)

        val match = matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNull(match)
    }

    @Test
    fun pairedMacMatcher_unpairedMacId_notMatched() {
        val idHex = idHexForDayOffset(otherFingerprint, now, 0)
        val matcher = matcherAt(now)

        val match = matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNull(match)
    }

    @Test
    fun pairedMacMatcher_malformedId_ignoredWithoutException() {
        val matcher = matcherAt(now)
        val malformedService = serviceAdvertising("not-hex-at-all")

        val match = matcher.match(malformedService, listOf(pairedFingerprint))

        assertNull(match)
    }

    @Test
    fun pairedMacMatcher_timeZoneUtcPlus14_usesUtcDayIndex() {
        val idHex = idHexForDayOffset(pairedFingerprint, now, 0)
        val utcMatcher = matcherAt(now, ZoneOffset.UTC)
        val plus14Matcher = matcherAt(now, ZoneOffset.ofHours(14))

        val utcMatch = utcMatcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))
        val plus14Match = plus14Matcher.match(serviceAdvertising(idHex), listOf(pairedFingerprint))

        assertNotNull(utcMatch)
        assertNotNull(plus14Match)
        assertEquals(utcMatch!!.fingerprint.base64Url, plus14Match!!.fingerprint.base64Url)
    }
}
