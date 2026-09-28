import Foundation
import TandemTestSupport
@testable import TandemPairing

/// `makeWindow` helpers for `PairingWindowTests`, split out to keep that file within the
/// type-length lint bounds.
extension PairingWindowTests {
    static func makeWindow(
        clock: ManualTestClock,
        verifier: any PairRequestVerifier
    ) -> (window: PairingWindow, clock: ManualTestClock) {
        let window = PairingWindow(dateProvider: FixedDateProvider(clock: clock).provider, proofVerifier: verifier)
        return (window, clock)
    }

    static func makeWindow(
        clock: ManualTestClock,
        verifierResult: Bool = true
    ) -> (window: PairingWindow, clock: ManualTestClock) {
        makeWindow(clock: clock, verifier: SpyPairRequestVerifier(result: verifierResult))
    }
}
