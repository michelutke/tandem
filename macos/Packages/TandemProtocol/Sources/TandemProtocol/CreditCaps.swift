/// Per-channel credit caps for flow control (SPEC.md `#channels-and-flow-control-credits`,
/// E01-04).
///
/// `CONTROL` carries no credit ledger and is exempt (SPEC.md, "CONTROL is exempt from credit
/// accounting"). Every other channel gets its own cap -- the maximum credit this side will ever
/// have outstanding to its peer on that channel -- chosen by the receiver, up to the protocol
/// maximum of 64 credits (`docs/planning/decisions.md` D-64). A new ``CreditLedger`` for a
/// channel starts with a balance equal to that channel's cap (the initial grant).
///
/// SPEC.md gives no per-channel numbers, so this is the single place Tandem's own chosen caps
/// live, mirroring the Android `core/protocol/flowcontrol/CreditCaps` object (E11-13). Every
/// feature channel currently uses the protocol maximum; a future issue may lower an individual
/// channel's cap (SPEC.md's own example is a memory-constrained phone picking a lower `FILES`
/// cap) by changing only this file.
///
/// Not `public`: the generated `Tandem_V1_Channel` this type's API is built on is itself
/// module-internal (`protocol/buf.gen.yaml` does not set `Visibility=Public` for the Swift
/// plugin), so nothing outside `TandemProtocol` can reference it yet.
enum CreditCaps {
    /// The protocol-wide maximum a chosen cap MUST NOT exceed (D-64).
    static let protocolMax: UInt32 = 64

    /// The cap Tandem uses for `channel`, and therefore ``CreditLedger``'s initial grant for it.
    ///
    /// - Precondition: `channel` must carry a credit ledger. `CONTROL`, `CHANNEL_UNSPECIFIED`,
    ///   and any unrecognized value never name a real feature channel (SPEC.md
    ///   `#channels-and-flow-control-credits`) and are rejected defensibly via a precondition,
    ///   matching ``CreditLedger``'s existing convention for caller-error input.
    static func capFor(_ channel: Tandem_V1_Channel) -> UInt32 {
        switch channel {
        case .notify, .clipboard, .files, .sms, .contacts, .calls, .input, .status, .mediaControl:
            return protocolMax
        case .control, .unspecified, .UNRECOGNIZED:
            preconditionFailure("\(channel) carries no credit ledger")
        }
    }
}
