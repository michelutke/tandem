package dev.tandem.core.pairing

import dev.tandem.core.pairing.qr.LiteralAddressValidator

/**
 * The Mac address an owner typed for manual pairing (ADR-008): a literal IP and a port, never a
 * hostname. It is only where to dial, never a trust anchor (invariant 3).
 */
class ManualPairingAddress private constructor(
    val host: String,
    val port: Int,
) {
    companion object {
        private const val MAX_PORT = 65_535

        /** Parses `a.b.c.d:port` or `[ipv6]:port`; `null` for anything else (hostnames, zones, bad ports). */
        fun parse(input: String): ManualPairingAddress? {
            val text = input.trim()
            val (host, portText) =
                if (text.startsWith("[")) {
                    val close = text.indexOf("]:")
                    if (close < 0) return null
                    text.substring(1, close) to text.substring(close + 2)
                } else {
                    val colon = text.lastIndexOf(':')
                    if (colon < 0 || text.indexOf(':') != colon) return null
                    text.substring(0, colon) to text.substring(colon + 1)
                }
            val port = portText.takeIf { p -> p.isNotEmpty() && p.all { it in '0'..'9' } }?.toIntOrNull()
            if (port == null || port !in 1..MAX_PORT) return null
            return if (LiteralAddressValidator.isAcceptableAddress(host)) ManualPairingAddress(host, port) else null
        }
    }
}
