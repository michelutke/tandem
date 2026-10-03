import Foundation
import TandemCrypto
import TandemStore

/// Production ``TrustStoreReader`` adapter over `TandemStore.TrustStore` (E13-06). Lives here,
/// rather than in `TandemStore` itself, because ``TrustStoreReader`` is this package's protocol and
/// the PRD's module rules put `TandemTransport` above `TandemStore` in the dependency graph
/// (`docs/PRD.md` "Layer 2: secure channel" -- `TandemTransport ← protocol, crypto, storage`); the
/// reverse dependency would form a package cycle back through `TandemTestSupport`, which already
/// depends on `TandemTransport` (`tools/lint/swift-package-rules.rb`, `swift package resolve`
/// confirm this direction is clean and the reverse is not).
///
/// SPEC.md §1 step 4 requires the candidate fingerprint compared, in constant time, "against every
/// fingerprint this side's trust store holds" -- not stopped at the first match. `TrustStore.get(_:)`
/// would instead perform a single Keychain lookup keyed by the candidate's own hex fingerprint,
/// short-circuiting on that lookup itself rather than comparing against every stored fingerprint, so
/// this reads every paired-peer record via ``TandemStore/TrustStore/list()`` and folds
/// ``TandemCrypto/SpkiFingerprint/matches(_:)`` (already constant time) over all of them with no
/// early exit.
public struct TandemTrustStoreReader: TrustStoreReader {
    private let trustStore: TrustStore
    private let dateProvider: DateProvider?

    /// - Parameter dateProvider: When set, an unexpired grace pin left by a key rotation (E70-05)
    ///   also verifies; `nil` (the default) accepts primary pins only.
    public init(trustStore: TrustStore, dateProvider: DateProvider? = nil) {
        self.trustStore = trustStore
        self.dateProvider = dateProvider
    }

    public func contains(_ fingerprint: SpkiFingerprint) throws -> Bool {
        var matched = false
        let now = dateProvider?()
        for record in try trustStore.list() {
            if record.fingerprint.matches(fingerprint) { matched = true }
            guard let now, let grace = record.gracePin, !grace.used, grace.expiresAt > now else { continue }
            if grace.fingerprint.matches(fingerprint) { matched = true }
        }
        return matched
    }
}
