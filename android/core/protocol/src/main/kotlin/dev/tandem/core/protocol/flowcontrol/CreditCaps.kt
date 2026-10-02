package dev.tandem.core.protocol.flowcontrol

import dev.tandem.protocol.v1.Channel

/**
 * Per-channel credit caps for flow control (SPEC.md #channels-and-flow-control-credits, E01-04).
 *
 * `CONTROL` carries no credit ledger and is exempt (SPEC.md, "CONTROL is exempt from credit
 * accounting"). Every other channel gets its own cap — the maximum credit this side will ever
 * have outstanding to its peer on that channel — chosen by the receiver, up to the protocol
 * maximum of 64 credits (`docs/planning/decisions.md` D-64). A new [CreditLedger] for a channel
 * starts with a balance equal to that channel's cap (the initial grant).
 *
 * This is the single place Tandem's own chosen caps live. Every feature channel currently uses
 * the protocol maximum; a future issue may lower an individual channel's cap (SPEC.md's own
 * example is a memory-constrained phone picking a lower `FILES` cap) by changing only this file.
 */
object CreditCaps {
    /** The protocol-wide maximum a chosen cap MUST NOT exceed (D-64). */
    const val PROTOCOL_MAX = 64

    /**
     * The cap Tandem uses for [channel], and therefore [CreditLedger]'s initial grant for it.
     *
     * @throws IllegalArgumentException if [channel] carries no credit ledger: `CONTROL`,
     *   `CHANNEL_UNSPECIFIED`, or an unrecognized value (SPEC.md #channels-and-flow-control-credits).
     */
    fun capFor(channel: Channel): Int =
        when (channel) {
            Channel.CHANNEL_NOTIFY,
            Channel.CHANNEL_CLIPBOARD,
            Channel.CHANNEL_FILES,
            Channel.CHANNEL_SMS,
            Channel.CHANNEL_CONTACTS,
            Channel.CHANNEL_CALLS,
            Channel.CHANNEL_INPUT,
            Channel.CHANNEL_STATUS,
            Channel.CHANNEL_MEDIA_CONTROL,
            -> {
                PROTOCOL_MAX
            }

            Channel.CHANNEL_CONTROL, Channel.CHANNEL_UNSPECIFIED, Channel.UNRECOGNIZED -> {
                throw IllegalArgumentException("$channel carries no credit ledger")
            }
        }
}
