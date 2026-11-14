import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
import TandemTransport
@testable import TandemPairing

private typealias Fixtures = PairConfirmationViewModelTests

/// The failure and abort paths of the mutual-confirmation dialog (E14-08, E14-16): a closed
/// connection, a released window slot, an expired window or a failing trust store each commit
/// nothing. Fixtures are shared with ``PairConfirmationViewModelTests``.
@Suite("PairConfirmationViewModelAbort")
struct PairConfirmationViewModelAbortTests {
    @Test
    func pairConfirmation_connectionClosedBeforePair_commitsNothing() async throws {
        let fixture = try Fixtures.loadFixture()
        let (window, token) = try Fixtures.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Fixtures.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        // The connection dropped on its own first: the flow layer already burned the attempt.
        window.releaseCandidate(token)
        viewModel.connectionDidClose()

        await viewModel.pair()
        await viewModel.dontPair()

        #expect(sink.calls.isEmpty)
        #expect(try trustStore.list().isEmpty)
        #expect(window.attemptsRemaining == 2)
    }

    @Test
    func pairConfirmation_connectionClosedThenPairClicked_didPairFalse() async throws {
        let fixture = try Fixtures.loadFixture()
        let (window, token) = try Fixtures.confirmationPendingWindow(secret: fixture.secret)
        let viewModel = try Fixtures.makeViewModel(fixture: fixture, window: window, token: token)

        window.releaseCandidate(token)
        viewModel.connectionDidClose()
        await viewModel.pair()

        #expect(!viewModel.didPair)
        #expect(viewModel.endedWithoutPairing)
    }

    @Test
    func pairConfirmation_accept_didPairTrueAndNotEndedWithoutPairing() async throws {
        let fixture = try Fixtures.loadFixture()
        let (window, token) = try Fixtures.confirmationPendingWindow(secret: fixture.secret)
        let viewModel = try Fixtures.makeViewModel(fixture: fixture, window: window, token: token)

        await viewModel.pair()

        #expect(viewModel.didPair)
        #expect(!viewModel.endedWithoutPairing)
    }

    /// E14-16 finding #3 (D-73): a second candidate's `PairRequest` frees this dialog's own slot
    /// (releasing it, per D-70) *before* the coordinator has a chance to mark this dialog resolved
    /// -- so `window.ownerAccepted(_:)` must itself refuse the transition, and `pair()` must
    /// commit nothing, even though this dialog's own `hasResolved` flag hasn't flipped yet.
    @Test
    func pairConfirmation_windowSlotReleasedByOtherMeansBeforePairClicked_commitsNothing() async throws {
        let fixture = try Fixtures.loadFixture()
        let (window, token) = try Fixtures.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Fixtures.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        // The window's own slot is released out from under this still-unresolved dialog (e.g. a
        // duplicate `PairRequest` on the same connection triggered `PairingCandidateFlow`'s own
        // `wrongPayloadReceived()` -> `releaseCandidate(_:)`, D-70) -- the dialog itself was never
        // told.
        window.releaseCandidate(token)

        await viewModel.pair()

        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
        #expect(try trustStore.list().isEmpty)
        #expect(viewModel.didFailToPair)
    }

    @Test
    func pairConfirmation_windowExpiredWhileDialogPending_pairAbortsNoPairAcceptedVisibleError() async throws {
        let fixture = try Fixtures.loadFixture()
        let clock = ManualTestClock()
        let (window, token) = try Fixtures.confirmationPendingWindow(secret: fixture.secret, clock: clock)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Fixtures.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        // The window's 120 s expiry elapses while the dialog is still showing, before the owner
        // clicks Pair (D-73's "commits nothing on a connection that is no longer open").
        clock.advance(by: .seconds(120))

        await viewModel.pair()

        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
        #expect(try trustStore.list().isEmpty)
        #expect(window.closedReason == .expired)
        #expect(viewModel.didFailToPair)
        #expect(!viewModel.didFailToCommit)
    }

    @Test
    func pairConfirmation_trustStoreCommitThrows_abortsNoPairAcceptedVisibleError() async throws {
        let fixture = try Fixtures.loadFixture()
        let (window, token) = try Fixtures.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let keychainStore = InMemoryKeychainStore()
        keychainStore.failNextOperation(with: .locked)
        let trustStore = TrustStore(keychainStore: keychainStore)
        let viewModel = try Fixtures.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        await viewModel.pair()

        #expect(sink.calls == [.pairRejected(.pairingUnavailable), .closePairingFailed])
        #expect(try trustStore.list().isEmpty)
        #expect(viewModel.didFailToPair)
        #expect(viewModel.didFailToCommit)
    }
}
