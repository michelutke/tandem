/// Per-channel credit-flow-control accounting (E01-04, `docs/protocol/SPEC.md`
/// `#channels-and-flow-control-credits`; D-64, `docs/planning/decisions.md`). Pure value type: no
/// concurrency, no I/O. One instance covers one feature channel for one direction; `CONTROL` is
/// exempt from credit accounting entirely and never gets a ledger (SPEC).
///
/// The credit unit is whole frames (SPEC: "one credit permits the sender to transmit exactly one
/// `Envelope` frame"). `cap` is this channel's configured cap -- the maximum credit this side will
/// ever have outstanding to its peer at one time, chosen by the receiver up to
/// ``CreditCaps/protocolMax`` (D-64: MUST NOT exceed 64). A new ledger's balance starts at `cap`
/// (SPEC: "a new ledger for a feature channel starts with a balance equal to that channel's
/// chosen cap").
///
/// Per D-64, an over-cap grant is reported rather than clamped, and consuming past zero is
/// rejected rather than clamped: this type never silently absorbs either condition, so
/// E11-08's multiplexer can close the connection with `CREDIT_VIOLATION` on either result.
public struct CreditLedger: Sendable, Equatable {
    /// This channel's configured cap: the balance `applyGrant(_:)` may never take the balance
    /// above (D-64).
    public let cap: UInt32

    public private(set) var balance: UInt32

    /// Result of `consume(_:)`.
    public enum ConsumeResult: Sendable, Equatable {
        case success
        case insufficient
    }

    /// Result of `applyGrant(_:)`.
    public enum GrantResult: Sendable, Equatable {
        case success
        case overflow
    }

    /// - Parameter cap: This channel's configured cap. Must be in `1...CreditCaps.protocolMax`
    ///   (D-64: MUST NOT exceed 64; a cap of 0 could never grant credit at all). A cap outside
    ///   that range is a caller programming error, not a runtime condition this type reports.
    public init(cap: UInt32) {
        let validRange = 1...CreditCaps.protocolMax
        precondition(validRange.contains(cap), "CreditLedger cap must be in \(validRange)")
        self.cap = cap
        self.balance = cap
    }

    /// Consumes `amount` credits (one credit per frame taken by the channel's application-level
    /// consumer, SPEC "Consume"). Returns `.insufficient` and leaves the balance unchanged if
    /// `amount` exceeds the current balance; the balance is never negative.
    ///
    /// - Precondition: `amount` must be positive. A caller never legitimately consumes zero
    ///   frames, so a non-positive `amount` is rejected defensibly via a precondition rather than
    ///   returning `.success`/`.insufficient`, matching this package's existing convention (see
    ///   `InMemoryConnectionPair.bufferCapacity`).
    @discardableResult
    public mutating func consume(_ amount: UInt32) -> ConsumeResult {
        precondition(amount > 0, "consume amount must be positive")
        guard amount <= balance else { return .insufficient }
        balance -= amount
        return .success
    }

    /// Applies a `CreditGrant.amount` (SPEC "Replenishment": restores the peer's balance,
    /// "never above" the cap). Returns `.overflow` and leaves the balance unchanged if applying
    /// `amount` would take the balance above `cap` -- D-64: reported, never clamped, so the
    /// caller can close the connection with `CREDIT_VIOLATION` instead of silently continuing.
    ///
    /// - Note: A wire `CreditGrant.amount` of `0` is a well-formed no-op (SPEC.md
    ///   `#channels-and-flow-control-credits`: "MUST be treated as a no-op, ignored"). This
    ///   method does not special-case it: the multiplexer (E11-08) must recognize a zero amount
    ///   itself and skip calling `applyGrant(_:)` entirely rather than rely on this pure-accounting
    ///   layer to do so.
    /// - Precondition: `amount` must be positive. Any non-positive `amount` reaching this method
    ///   is therefore a caller error, not a genuine zero-amount grant, and is rejected defensibly
    ///   via a precondition.
    @discardableResult
    public mutating func applyGrant(_ amount: UInt32) -> GrantResult {
        precondition(amount > 0, "grant amount must be positive")
        guard amount <= cap - balance else { return .overflow }
        balance += amount
        return .success
    }
}
