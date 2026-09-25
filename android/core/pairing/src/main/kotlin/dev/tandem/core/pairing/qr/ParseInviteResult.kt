package dev.tandem.core.pairing.qr

/** Outcome of [QrPayloadParser.parse]. */
sealed class ParseInviteResult {
    data class Accepted(
        val invite: PairingInvite,
    ) : ParseInviteResult()

    data class Rejected(
        val error: InviteError,
    ) : ParseInviteResult()
}
