import Foundation
import Testing
import TandemTestSupport
@testable import TandemPairing

/// ``PairingWindow/ownerAccepted(_:)``'s two edge cases (cycle 8 adversarial review, D-73): the
/// secret buffer is scrubbed in place, not merely dropped, and a window that expired while the
/// confirmation dialog was showing refuses the `.paired` transition instead of committing it late.
/// Split out of `PairingWindowTests` to keep both files under the project's type-body-length
/// limit -- the rest of the candidate-token safety net (a stale caller from a since-released or
/// since-replaced candidate can only ever no-op) is covered there
/// ("E14-16 finding #2: generation-token scoping").
@Suite("PairingWindow candidate tokens")
struct PairingWindowCandidateTokenTests {

    @Test
    func pairingWindow_ownerAccepted_secretBytesActuallyZeroed() throws {
        let window = Self.makeWindow(clock: ManualTestClock()).window
        window.open(secret: Data([0xAA, 0xBB, 0xCC]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)
        let box = try #require(window.secretBoxForTesting)

        #expect(window.ownerAccepted(token))

        // The literal same buffer `submitPairRequest` read from is scrubbed in place, not merely
        // dropped -- `secretBoxForTesting == nil` alone doesn't prove that.
        #expect(box.bytes.allSatisfy { $0 == 0 })
    }

    @Test
    func pairingWindow_ownerAccepted_windowExpiredWhileDialogPending_noOpReturnsFalse() throws {
        let clock = ManualTestClock()
        let window = Self.makeWindow(clock: clock).window
        window.open(secret: Data([1]))
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        #expect(window.submitPairRequest(token, proof: Data([9])) == .pendingConfirmation)

        clock.advance(by: .seconds(120))

        #expect(!window.ownerAccepted(token))
        #expect(window.closedReason == .expired)
    }

    private static func makeWindow(
        clock: ManualTestClock,
        verifierResult: Bool = true
    ) -> (window: PairingWindow, clock: ManualTestClock) {
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SpyPairRequestVerifier(result: verifierResult)
        )
        return (window, clock)
    }
}
