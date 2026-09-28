#if DEBUG
import Foundation
import Security
import TandemCrypto
import TandemTransport

/// E21-07: the `-HarnessPrintRotatingId` one-shot hook, split out of `HarnessHooks.swift` purely
/// to keep that file under this repo's `file_length`/`type_body_length` lint budgets.
extension HarnessHooks {
    /// Prints the rotating id (E21-02 ``DiscoveryRotatingId``) this Mac's identity would advertise
    /// for `pinnedDateIso8601` -- the exact same
    /// `DiscoveryRotatingId.computeHex(macSpkiFingerprint:dayIndex:)` call
    /// ``TandemTransport/BonjourAdvertiser`` makes from its own injected `DateProvider`, just
    /// pinned to a CI-supplied instant instead of the real wall clock, so the E15-15-style
    /// integration harness can prove a phone's rotating-id recognition across a real day-boundary
    /// or skew case without either process needing to change its actual clock or run real mDNS
    /// multicast. Never a trust decision on its own (invariant 3) -- the harness's already-real
    /// mTLS/pin-check path (`-HarnessListenerPort`/`-HarnessSeedTrust`) is untouched by this hook.
    static func printRotatingId(pinnedDateIso8601: String) {
        guard let pinnedDate = ISO8601DateFormatter().date(from: pinnedDateIso8601) else {
            fatalError("-HarnessPrintRotatingId requires a valid ISO 8601 date, got \(pinnedDateIso8601)")
        }
        let keychainStore = KeychainStoreFactory.make()
        let identityBootstrapper = IdentityBootstrapper(keychainStore: keychainStore)
        identityBootstrapper.bootstrapIdentity()
        guard case .ready(let identity) = identityBootstrapper.identityState else {
            let state = identityBootstrapper.identityState
            fatalError("-HarnessPrintRotatingId requested but identity is not ready: \(state)")
        }
        printIdentitySpkiFingerprint(identity: identity)

        guard let macSpkiDer = spkiDer(for: identity),
              let fingerprint = try? SpkiFingerprint.of(spkiDer: macSpkiDer) else {
            fatalError("-HarnessPrintRotatingId requested but the harness identity's SPKI could not be read")
        }
        let dayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc: Int64(pinnedDate.timeIntervalSince1970))
        let idHex = DiscoveryRotatingId.computeHex(macSpkiFingerprint: fingerprint.bytes, dayIndex: dayIndex)
        print("harness-rotating-id: \(idHex)")
        fflush(stdout)
    }
}
#endif
