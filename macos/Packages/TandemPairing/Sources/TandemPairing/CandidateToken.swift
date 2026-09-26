import Foundation

/// Proof that a caller's earlier ``PairingWindow/admitCandidateToken()`` claimed *this* window's
/// single candidate slot, required by every later mutation of the same candidate. A token from a
/// since-released or since-replaced candidate no longer matches the slot's current occupant, so a
/// stale caller (e.g. a transport close callback firing late) can only ever no-op instead of
/// mutating -- or burning an attempt for -- whichever candidate currently holds the slot
/// (`docs/planning/decisions.md` D-73, adversarial-verifier finding).
public struct CandidateToken: Sendable, Equatable {
    private let id: UUID

    init() {
        self.id = UUID()
    }
}
