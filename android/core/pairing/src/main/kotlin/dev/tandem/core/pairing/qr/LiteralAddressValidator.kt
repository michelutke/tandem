package dev.tandem.core.pairing.qr

/**
 * Hand-rolled validator for SPEC.md §2's `literal-addr` production (RFC 3986 §3.2.2's
 * `IPv4address` / `IPv6address`, no zone ID) plus the `a` field's semantic reject rules
 * (unspecified, multicast, broadcast). Deliberately not `java.net.InetAddress` (which accepts a
 * `%zone` suffix and may differ from RFC 3986 on leading-zero octets) and not `android.net.Uri`
 * (this module is pure JVM, testable off-device). Mirrors `tools/vectors/qr_payload.py`'s use of
 * Python's `ipaddress` module.
 */
internal object LiteralAddressValidator {
    private const val IPV4_BYTES = 4
    private const val IPV6_BYTES = 16
    private const val IPV6_GROUP_COUNT = 8
    private const val IPV4_MULTICAST_LOW = 224
    private const val IPV4_MULTICAST_HIGH = 239
    private const val HEX_RADIX = 16
    private const val BYTE_BITS = 8
    private const val BYTE_MASK = 0xFF

    // RFC 3986 `dec-octet` (no leading zero except the lone digit "0") and `h16` (1*4HEXDIG).
    private val DEC_OCTET = Regex("^(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    private val H16 = Regex("^[0-9a-fA-F]{1,4}$")

    /** True if [candidate] is a valid, non-forbidden `literal-addr` per SPEC.md §2's `a` field rule. */
    fun isAcceptableAddress(candidate: String): Boolean {
        if (candidate.isEmpty() || '%' in candidate) return false
        val ipv4 = parseIpv4(candidate)
        return if (ipv4 != null) {
            !isForbidden(ipv4, isIpv4 = true)
        } else {
            val ipv6 = parseIpv6(candidate)
            ipv6 != null && !isForbidden(ipv6, isIpv4 = false)
        }
    }

    private fun isForbidden(
        bytes: ByteArray,
        isIpv4: Boolean,
    ): Boolean {
        if (bytes.all { it == 0.toByte() }) return true
        val firstByte = bytes[0].toInt() and BYTE_MASK
        return if (isIpv4) {
            firstByte in IPV4_MULTICAST_LOW..IPV4_MULTICAST_HIGH || bytes.all { it == BYTE_MASK.toByte() }
        } else {
            firstByte == BYTE_MASK
        }
    }

    /** RFC 3986 `IPv4address = dec-octet "." dec-octet "." dec-octet "." dec-octet`. */
    private fun parseIpv4(candidate: String): ByteArray? {
        val parts = candidate.split(".")
        if (parts.size != IPV4_BYTES || parts.any { !DEC_OCTET.matches(it) }) return null
        return parts.map { it.toInt().toByte() }.toByteArray()
    }

    /** RFC 3986 `IPv6address`; `ls32` may be an embedded [parseIpv4] in the last group. */
    private fun parseIpv6(candidate: String): ByteArray? {
        if (":::" in candidate) return null
        val doubleColonIndex = candidate.indexOf("::")
        return if (doubleColonIndex < 0) {
            val groups = candidate.split(":")
            if (unitCount(groups) != IPV6_GROUP_COUNT) null else assembleGroups(groups)
        } else {
            parseCompressed(candidate, doubleColonIndex)
        }
    }

    private fun parseCompressed(
        candidate: String,
        doubleColonIndex: Int,
    ): ByteArray? {
        if (candidate.indexOf("::", doubleColonIndex + 1) >= 0) return null
        val left = candidate.substring(0, doubleColonIndex)
        val right = candidate.substring(doubleColonIndex + 2)
        val leftGroups = if (left.isEmpty()) emptyList() else left.split(":")
        val rightGroups = if (right.isEmpty()) emptyList() else right.split(":")

        return if (unitCount(leftGroups) + unitCount(rightGroups) >= IPV6_GROUP_COUNT) {
            null
        } else {
            assembleGroups(leftGroups)?.let { leftBytes ->
                assembleGroups(rightGroups)?.let { rightBytes ->
                    val out = ByteArray(IPV6_BYTES)
                    leftBytes.copyInto(out, destinationOffset = 0)
                    rightBytes.copyInto(out, destinationOffset = IPV6_BYTES - rightBytes.size)
                    out
                }
            }
        }
    }

    /** Counts 16-bit units [groups] represents; an embedded [parseIpv4] in the last slot counts as 2. */
    private fun unitCount(groups: List<String>): Int =
        if (groups.isNotEmpty() && "." in groups.last()) groups.size + 1 else groups.size

    /** Assembles [groups] into bytes; the last group may be an embedded [parseIpv4] address. */
    private fun assembleGroups(groups: List<String>): ByteArray? {
        if (groups.isEmpty()) return ByteArray(0)
        val hasEmbeddedIpv4 = "." in groups.last()
        val h16Groups = if (hasEmbeddedIpv4) groups.dropLast(1) else groups
        return if (h16Groups.any { !H16.matches(it) }) {
            null
        } else {
            val h16Bytes = assembleH16(h16Groups)
            if (!hasEmbeddedIpv4) h16Bytes else parseIpv4(groups.last())?.let { h16Bytes + it }
        }
    }

    private fun assembleH16(groups: List<String>): ByteArray {
        val bytes = ByteArray(groups.size * 2)
        for ((index, group) in groups.withIndex()) {
            val value = group.toInt(HEX_RADIX)
            bytes[index * 2] = (value shr BYTE_BITS).toByte()
            bytes[index * 2 + 1] = (value and BYTE_MASK).toByte()
        }
        return bytes
    }
}
