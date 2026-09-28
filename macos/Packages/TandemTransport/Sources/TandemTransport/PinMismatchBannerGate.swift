import Foundation

/// Counts verify-callback ``PeerAuthorizationDecision/rejected`` outcomes (E12-02, ``PeerVerifier``)
/// as the D-59 / AC-13 "aggregate, non-blocking counter" for pre-authentication noise --
/// `docs/planning/decisions.md` D-59: "Pre-authentication closes are not surfaced per connection."
///
/// On the Mac listener, a `.rejected` outcome is BY DEFINITION a pre-pin-check close: the peer
/// never passed the pin check (SPEC.md "Pre-authentication closes are not surfaced per
/// connection"). Per `docs/planning/decisions.md` D-23, the rejecting side cannot distinguish an
/// unrecognized key from a previously-revoked or previously-pinned-and-changed one -- there is no
/// signal available pre-auth that lets this Mac tell those cases apart -- so no rejection here may
/// ever pop a per-connection banner, regardless of whether the trust store is empty or not
/// (`docs/planning/decisions.md` D-76). This type is intentionally counter-only infrastructure: a
/// future post-pin-check producer (E22-02) is the earliest point a real per-connection banner
/// event could legitimately originate.
public actor PinMismatchBannerGate {
    /// Every verify-callback rejection this gate has ever recorded -- the D-59 "aggregate,
    /// non-blocking counter" for pre-pin-check noise.
    public private(set) var rejectionCount = 0

    public init() {}

    /// Records one verify-callback ``PeerAuthorizationDecision/rejected`` outcome (SPEC.md §1):
    /// bumps ``rejectionCount`` only. Callers must invoke this only for `.rejected` decisions;
    /// ``PeerVerifier`` never records `.trusted`/`.pairingCandidate` here, since neither is a
    /// pin-mismatch signal.
    public func recordRejection() {
        rejectionCount += 1
    }
}
