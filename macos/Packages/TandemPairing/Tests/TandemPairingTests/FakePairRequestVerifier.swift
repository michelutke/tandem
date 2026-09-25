import Foundation
@testable import TandemPairing

/// A ``PairRequestVerifier`` fake whose result and call count are inspectable -- used to prove
/// ``PairingWindow`` invokes it exactly when SPEC.md says to (e.g. never for a 4th attempt) and
/// never for anything else.
final class SpyPairRequestVerifier: PairRequestVerifier, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var result: Bool

    init(result: Bool) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func verify(proof: Data, secret: Data, challenge: Data) -> Bool {
        lock.lock()
        count += 1
        lock.unlock()
        return result
    }
}

/// A ``PairRequestVerifier`` fake that only accepts a proof computed against one specific secret
/// -- stands in for the real HMAC/transcript check (E14-07) to prove a regenerated window's new
/// secret rejects a proof computed against the old one.
struct SecretEqualityPairRequestVerifier: PairRequestVerifier {
    let expectedSecret: Data

    func verify(proof: Data, secret: Data, challenge: Data) -> Bool {
        secret == expectedSecret
    }
}
