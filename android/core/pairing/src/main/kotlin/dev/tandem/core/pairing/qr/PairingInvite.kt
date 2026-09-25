package dev.tandem.core.pairing.qr

/**
 * A parsed and fully validated `tandem://pair` payload (SPEC.md §2, E01-21). [fingerprint] is the
 * Mac's 32-byte SPKI SHA-256 fingerprint; [secret] is the 16-byte, CSPRNG-generated, single-use
 * pairing secret — sensitive, and MUST NOT be logged: [toString] never includes its bytes. [addresses]
 * is 1 to 8 literal IPv4/IPv6 addresses in the order the QR listed them. [macName] is the `n` field
 * after percent-decoding and [dev.tandem.core.protocol.DisplayStringSanitizer] sanitization (E14-21);
 * it is never trusted for any decision, only for display.
 */
class PairingInvite(
    val fingerprint: ByteArray,
    val secret: ByteArray,
    val addresses: List<String>,
    val port: Int,
    val macName: String,
) {
    override fun toString(): String =
        "PairingInvite(fingerprint=${fingerprint.size}B, secret=REDACTED, " +
            "addresses=$addresses, port=$port, macName=$macName)"
}
