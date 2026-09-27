import Foundation

/// D-64/D-57 flow-control bookkeeping split out of `ChannelMultiplexer.swift` itself purely to
/// keep that file under this repo's `file_length` lint budget -- every member here still runs
/// actor-isolated on `ChannelMultiplexer`, reading/writing its stored state exactly as if it were
/// declared in the main file (hence `internal`, not `private`, on the handful of properties/
/// methods these three touch: `sendLedger`, `receiveLedger`, `consumedSinceLastGrant`,
/// `outgoingSeq`, `inboundWatermark`, `inboundPendingAboveWatermark`, `kickDrainIfNeeded()`,
/// `Self.featureChannels`).
extension ChannelMultiplexer {
    /// Applies a peer's `CreditGrant` to this side's own send-side balance for the channel it
    /// names (docs/protocol/SPEC.md #channels-and-flow-control-credits "Replenishment"). A
    /// `CreditGrant` naming `.control`, `.unspecified`, or any unrecognized value is rejected
    /// `MALFORMED_FRAME`/`unknownChannel` (SPEC.md: those never name a real credit ledger). An
    /// `amount` of 0 is a well-formed no-op. An `amount` that would push this side's balance for
    /// that channel above its cap is a ``MultiplexerClose/creditViolation(_:)`` (D-64: reported,
    /// never clamped) -- also unblocking nothing, since nothing changed.
    ///
    /// - Returns: `false` (having already called `finish(_:)`) on either violation.
    func applyIncomingCreditGrant(_ grant: Tandem_V1_CreditGrant) async -> Bool {
        let namedChannel = grant.channel
        guard Self.featureChannels.contains(namedChannel) else {
            await finish(.violation(.malformedFrame, .unknownChannel))
            return false
        }
        guard grant.amount > 0 else { return true }

        guard let result = sendLedger[namedChannel]?.applyGrant(grant.amount) else { return true }
        switch result {
        case .success:
            kickDrainIfNeeded()
            return true
        case .overflow:
            await finish(.creditViolation(namedChannel))
            return false
        }
    }

    /// Records that a caller actually pulled `channel`'s frame off ``inbound(_:)``'s stream
    /// (docs/protocol/SPEC.md "Consume": application-level consumption, not decode, is what a
    /// replenishment grant is conditioned on). Once accumulated consumption since the last grant
    /// this side sent for `channel` reaches half its cap, sends the peer exactly one `CreditGrant`
    /// restoring this side's belief of the peer's balance to exactly the cap
    /// (`docs/planning/decisions.md` D-64: "never above"), then resets the accumulator so the
    /// trigger re-arms against the next half-cap crossing.
    func frameConsumed(_ channel: Tandem_V1_Channel) async {
        guard channel != .control else { return }
        let cap = CreditCaps.capFor(channel)

        let consumedCount = (consumedSinceLastGrant[channel] ?? 0) + 1
        consumedSinceLastGrant[channel] = consumedCount
        guard consumedCount >= cap / 2 else { return }

        let currentBalance = receiveLedger[channel]?.balance ?? cap
        let amount = cap - currentBalance
        consumedSinceLastGrant[channel] = 0
        guard amount > 0 else { return }

        _ = receiveLedger[channel]?.applyGrant(amount)

        var grant = Tandem_V1_CreditGrant()
        grant.channel = channel
        grant.amount = amount
        try? await send(.control, payload: .creditGrant(grant))
    }

    /// - Returns: the violation reason if `seq` or `ack` violates D-57 (a `seq` of 0, at or below
    ///   the current watermark, or a duplicate of an already-received above-watermark value; an
    ///   `ack` above the highest `seq` this side has itself sent on `channel`; or `channel`'s
    ///   above-watermark pending set already holding ``CreditCaps/protocolMax`` entries -- D-64: a
    ///   legitimate, credit-bound peer can never make this many `seq` values pending at once). On
    ///   success (`nil`), records `seq` and advances the watermark past any newly-contiguous run
    ///   (docs/protocol/SPEC.md "Sequence and acknowledgement violations").
    func validateAndRecord(seq: UInt64, ack: UInt64, channel: Tandem_V1_Channel) -> MalformedFrameReason? {
        guard ack <= (outgoingSeq[channel] ?? 0) else { return .seqRegression }

        var watermark = inboundWatermark[channel] ?? 0
        var pending = inboundPendingAboveWatermark[channel] ?? []
        guard seq > watermark, !pending.contains(seq) else { return .seqRegression }
        guard pending.count < Int(CreditCaps.protocolMax) else { return .seqGapTooLarge }

        pending.insert(seq)
        while pending.contains(watermark + 1) {
            watermark += 1
            pending.remove(watermark)
        }

        inboundWatermark[channel] = watermark
        inboundPendingAboveWatermark[channel] = pending
        return nil
    }
}
