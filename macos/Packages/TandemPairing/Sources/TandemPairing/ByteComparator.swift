import Foundation
import TandemCrypto

/// Seam for the final proof comparison (E14-07, `docs/protocol/SPEC.md` §2 "Proof computation",
/// invariant 6) -- lets tests substitute a spy that counts invocations, proving ``PairProofVerifier``
/// calls it exactly once per attempt, without weakening what the production path actually compares
/// with.
public protocol ByteComparator: Sendable {
    func compare(_ lhs: Data, _ rhs: Data) -> Bool
}

/// Production ``ByteComparator``: TandemCrypto's E10-11 constant-time compare, unchanged.
public struct ConstantTimeByteComparator: ByteComparator {
    public init() {}

    public func compare(_ lhs: Data, _ rhs: Data) -> Bool {
        constantTimeEquals(lhs, rhs)
    }
}
