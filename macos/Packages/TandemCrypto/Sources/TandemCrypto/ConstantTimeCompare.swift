import Foundation

/// Constant-time equality check for secrets (invariant 6): no data-dependent branching or early
/// exit once the lengths are known to match. Used by pairing-proof verification (E14-07).
public func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
    constantTimeEquals(lhs, rhs, counter: ByteAccessCounter())
}

/// Test seam (E10-11): counts every byte read so tests can assert the compare always scans the
/// full length, regardless of where the first mismatch is. Not exported from TandemCrypto.
final class ByteAccessCounter {
    private(set) var accessCount = 0

    func record() {
        accessCount += 1
    }
}

func constantTimeEquals(_ lhs: Data, _ rhs: Data, counter: ByteAccessCounter) -> Bool {
    guard lhs.count == rhs.count else { return false }

    let lhsBytes = [UInt8](lhs)
    let rhsBytes = [UInt8](rhs)
    var diff: UInt8 = 0
    for index in lhsBytes.indices {
        counter.record()
        let lhsByte = lhsBytes[index]
        counter.record()
        let rhsByte = rhsBytes[index]
        diff |= lhsByte ^ rhsByte
    }
    return diff == 0
}
