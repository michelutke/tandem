package dev.tandem.core.pairing.qr

/**
 * Per-field validators for [QrPayloadParser] (SPEC.md §2's `pair-uri` field rules), one function
 * per field beyond `v` and the required-field/duplicate-field checks `QrPayloadParser` itself
 * handles. Each returns `null` when the raw field value is valid.
 */
internal object QrFieldValidation {
    private const val FINGERPRINT_BYTES = 32
    private const val SECRET_BYTES = 16
    private const val MAX_ADDRESSES = 8
    private const val MAX_NAME_BYTES = 64
    private const val MIN_PORT = 1
    private const val MAX_PORT = 65535
    private const val MAX_PORT_DIGITS = 5

    fun versionError(raw: String): InviteError? = if (raw != "1") InviteError.UnsupportedVersion else null

    fun fingerprintError(raw: String): InviteError? {
        val decoded = QrEncoding.decodeBase64Url(raw) ?: return InviteError.InvalidEncoding("fp")
        return if (decoded.size != FINGERPRINT_BYTES) InviteError.InvalidFingerprint else null
    }

    fun secretError(raw: String): InviteError? {
        val decoded = QrEncoding.decodeBase64Url(raw) ?: return InviteError.InvalidEncoding("s")
        return if (decoded.size != SECRET_BYTES) InviteError.InvalidSecret else null
    }

    fun addressListError(raw: String): InviteError? {
        if (raw.isEmpty()) return InviteError.InvalidAddress
        val candidates = raw.split(",")
        return when {
            candidates.size > MAX_ADDRESSES -> InviteError.TooManyAddresses
            candidates.any { !LiteralAddressValidator.isAcceptableAddress(it) } -> InviteError.InvalidAddress
            else -> null
        }
    }

    fun portError(raw: String): InviteError? = if (parsePort(raw) == null) InviteError.InvalidPort else null

    fun nameError(raw: String): InviteError? =
        if (QrEncoding.percentDecode(raw).size > MAX_NAME_BYTES) InviteError.InvalidName else null

    fun parsePort(raw: String): Int? {
        if (!isAllDigits(raw) || raw.length > MAX_PORT_DIGITS || hasLeadingZero(raw)) return null
        return raw.toIntOrNull()?.takeIf { it in MIN_PORT..MAX_PORT }
    }

    private fun isAllDigits(raw: String): Boolean = raw.isNotEmpty() && raw.all { it in '0'..'9' }

    private fun hasLeadingZero(raw: String): Boolean = raw.length > 1 && raw[0] == '0'
}
