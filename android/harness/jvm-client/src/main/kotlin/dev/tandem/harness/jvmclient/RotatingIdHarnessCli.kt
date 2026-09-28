package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.discovery.ResolvedService
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.system.exitProcess

/**
 * E21-07: a standalone JVM CLI wrapping the real Android [PairedMacMatcher] (`core/discovery`) so
 * the cross-platform integration harness (`tools/harness/integration/e21-07.sh`) can prove
 * rotating-id recognition against a real Mac-produced id (printed by `HarnessHooks`'
 * `-HarnessPrintRotatingId`, macos/TandemApp) without either process touching its actual wall
 * clock or running real mDNS multicast -- this CLI's own clock is a [Clock.fixed] built from the
 * phone-side instant the shell script passes in.
 *
 * Invariant 3 (CLAUDE.md): recognition here is a connection-candidate hint only -- this CLI never
 * performs or claims to perform any trust decision, exactly like [PairedMacMatcher] itself; it
 * exists only to prove the +/-1 day skew window and day-boundary case cross-platform, not to stand
 * in for the mTLS pin check.
 *
 * Usage: `<macSpkiFingerprintHex> <macRotatingIdHex> <phoneInstantIso8601>`. Prints `RECOGNIZED`
 * and exits 0 if [PairedMacMatcher.match] finds [macSpkiFingerprintHex] among a single-candidate
 * paired-fingerprint list; otherwise prints `NOT_RECOGNIZED` and exits 1.
 */
fun main(args: Array<String>) {
    require(args.size == THREE_ARGS) {
        "usage: RotatingIdHarnessCliKt <macSpkiFingerprintHex> <macRotatingIdHex> <phoneInstantIso8601>"
    }
    val (macSpkiFingerprintHex, macRotatingIdHex, phoneInstantIso8601) = args
    val fingerprint = SpkiFingerprint(hexToBytes(macSpkiFingerprintHex))
    val phoneInstant = Instant.parse(phoneInstantIso8601)
    val matcher = PairedMacMatcher(Clock.fixed(phoneInstant, ZoneOffset.UTC))
    val service =
        ResolvedService(
            serviceName = "e21-07-harness-mac",
            host = "127.0.0.1",
            port = 5353,
            txtRecords = mapOf("v" to "1", "id" to macRotatingIdHex),
        )

    if (matcher.match(service, listOf(fingerprint)) != null) {
        println("RECOGNIZED")
    } else {
        println("NOT_RECOGNIZED")
        exitProcess(1)
    }
}

private const val THREE_ARGS = 3

private fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) { i ->
        ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
    }
