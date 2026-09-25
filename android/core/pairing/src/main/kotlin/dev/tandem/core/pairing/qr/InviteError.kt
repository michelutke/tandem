package dev.tandem.core.pairing.qr

/**
 * Reject reason for [QrPayloadParser.parse] (SPEC.md §2, E01-21). Mirrors
 * `tools/vectors/qr_payload.py`'s error taxonomy exactly, one type per `expectedError` value in
 * `protocol/vectors/qr-payload.json`: missingRequiredField, duplicatedField, invalidEncoding,
 * invalidFingerprint, invalidSecret, invalidPort, invalidAddress, tooManyAddresses, invalidName,
 * unsupportedVersion, invalidScheme, invalidHost. [field] names the single query field responsible,
 * where the taxonomy defines one — null for [InvalidScheme]/[InvalidHost], which fail before any
 * field is parsed.
 */
sealed class InviteError {
    abstract val field: String?

    data class MissingRequiredField(
        override val field: String,
    ) : InviteError()

    data class DuplicatedField(
        override val field: String,
    ) : InviteError()

    data class InvalidEncoding(
        override val field: String,
    ) : InviteError()

    data object InvalidFingerprint : InviteError() {
        override val field = "fp"
    }

    data object InvalidSecret : InviteError() {
        override val field = "s"
    }

    data object InvalidPort : InviteError() {
        override val field = "p"
    }

    data object InvalidAddress : InviteError() {
        override val field = "a"
    }

    data object TooManyAddresses : InviteError() {
        override val field = "a"
    }

    data object InvalidName : InviteError() {
        override val field = "n"
    }

    data object UnsupportedVersion : InviteError() {
        override val field = "v"
    }

    data object InvalidScheme : InviteError() {
        override val field: String? = null
    }

    data object InvalidHost : InviteError() {
        override val field: String? = null
    }
}
