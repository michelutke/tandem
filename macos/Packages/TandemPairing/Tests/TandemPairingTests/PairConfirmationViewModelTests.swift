import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
import TandemTransport
@testable import TandemPairing

/// The Mac's mutual-confirmation dialog (E14-08, `docs/protocol/SPEC.md` § Pairing, "Mutual
/// confirmation"). Every fixture here drives a real ``PairingWindow`` to `.confirmationPending`
/// exactly like ``PairingCandidateFlowTests`` drives it to failure, using the same
/// `pairing-proof.json` vector both `TandemCryptoTests` and `PairProofVerifierTests` already
/// validate, so the confirmation code and phone SPKI here are real, mutually-consistent values --
/// not ad hoc bytes.
@Suite("PairConfirmationViewModel")
struct PairConfirmationViewModelTests {

    @Test
    func pairConfirmation_phoneNamePixel8_titleIsPairPixel8Question() throws {
        let viewModel = try Self.makeViewModel(displayName: "Pixel 8")
        #expect(viewModel.title == "Pair Pixel 8?")
    }

    @Test
    func pairConfirmation_body_showsModelAndSixDigitCode() throws {
        let fixture = try Self.loadFixture()
        let viewModel = try Self.makeViewModel(model: "Google Pixel 8", fixture: fixture)
        let grouped = Self.grouped(fixture.confirmationCode)
        #expect(viewModel.bodyText == "Google Pixel 8 · Make sure your phone shows \(grouped)")
    }

    @Test
    func pairConfirmation_accept_sendsPairAcceptedAndCommitsHandshakeSpki() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Self.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        await viewModel.pair()

        #expect(sink.calls == [.pairAccepted])
        #expect(window.closedReason == .paired)
        let records = try trustStore.list()
        #expect(records.count == 1)
        #expect(records.first?.fingerprint == (try SpkiFingerprint.of(spkiDer: fixture.phoneSpkiDer)))
    }

    @Test
    func pairConfirmation_accept_onPairedCalledOnceBeforePairAccepted() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let onPairedCallCount = LockedBox(0)
        let viewModel = try Self.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            onPaired: { onPairedCallCount.value += 1 }
        )

        await viewModel.pair()

        #expect(onPairedCallCount.value == 1)
    }

    @Test
    func pairConfirmation_deny_sendsPairRejectedAndClosesEntireWindow() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Self.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        await viewModel.dontPair()

        #expect(sink.calls == [.pairRejected(.rejectedByOwner), .closePairingFailed])
        #expect(window.closedReason == .declined)
        #expect(try trustStore.list().isEmpty)
    }

    @Test
    func pairConfirmation_ownerInitiatedDismissConnectionStillOpen_closesEntireWindow() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let viewModel = try Self.makeViewModel(fixture: fixture, window: window, token: token, sink: sink)

        await viewModel.ownerDidDismiss()

        #expect(sink.calls == [.pairRejected(.rejectedByOwner), .closePairingFailed])
        #expect(window.closedReason == .declined)
    }

    @Test
    func pairConfirmation_defaultAndEscapeAction_isDontPair() {
        #expect(PairConfirmationViewModel.defaultAction == .dontPair)
        #expect(PairConfirmationViewModel.escapeAction == .dontPair)
    }

    @Test
    func pairConfirmation_nameWithBidiOverride_displayedSanitized() throws {
        let bidiName = "\u{202E}evil\u{202C}Pixel"
        let viewModel = try Self.makeViewModel(displayName: bidiName)

        #expect(!viewModel.title.unicodeScalars.contains { $0.value == 0x202E })
        #expect(!viewModel.title.unicodeScalars.contains { $0.value == 0x202C })
    }

    @Test
    func pairConfirmation_connectionClosedBeforePair_commitsNothing() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Self.makeViewModel(
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

    /// E14-16 finding #3 (D-73): a second candidate's `PairRequest` frees this dialog's own slot
    /// (releasing it, per D-70) *before* the coordinator has a chance to mark this dialog resolved
    /// -- so `window.ownerAccepted(_:)` must itself refuse the transition, and `pair()` must
    /// commit nothing, even though this dialog's own `hasResolved` flag hasn't flipped yet.
    @Test
    func pairConfirmation_windowSlotReleasedByOtherMeansBeforePairClicked_commitsNothing() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Self.makeViewModel(
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

        #expect(sink.calls.isEmpty)
        #expect(try trustStore.list().isEmpty)
        #expect(viewModel.didFailToPair)
    }

    @Test
    func pairConfirmation_windowExpiredWhileDialogPending_pairAbortsNoPairAcceptedVisibleError() async throws {
        let fixture = try Self.loadFixture()
        let clock = ManualTestClock()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret, clock: clock)
        let sink = FakePairingCandidateSink()
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let viewModel = try Self.makeViewModel(
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

        #expect(sink.calls.isEmpty)
        #expect(try trustStore.list().isEmpty)
        #expect(window.closedReason == .expired)
        #expect(viewModel.didFailToPair)
    }

    @Test
    func pairConfirmation_trustStoreCommitThrows_abortsNoPairAcceptedVisibleError() async throws {
        let fixture = try Self.loadFixture()
        let (window, token) = Self.confirmationPendingWindow(secret: fixture.secret)
        let sink = FakePairingCandidateSink()
        let keychainStore = InMemoryKeychainStore()
        keychainStore.failNextOperation(with: .locked)
        let trustStore = TrustStore(keychainStore: keychainStore)
        let viewModel = try Self.makeViewModel(
            fixture: fixture,
            window: window,
            token: token,
            sink: sink,
            trustStore: trustStore
        )

        await viewModel.pair()

        #expect(sink.calls.isEmpty)
        #expect(try trustStore.list().isEmpty)
        #expect(viewModel.didFailToPair)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let secret: Data
        let phoneSpkiDer: Data
        let confirmationCode: String
    }

    private static func loadFixture() throws -> Fixture {
        let manifest = try PairingProofVectorFixture.load()
        guard let entry = manifest.vectors.first(where: { $0.id == "pairing-proof-correct-a" }) else {
            struct MissingVector: Error {}
            throw MissingVector()
        }
        let secret = try PairingProofVectorFixture.secret(for: entry)
        let macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
        let phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
        let channelBinding = try PairingProofVectorFixture.channelBinding(for: entry)
        let confirmationCode = try ConfirmationCode.compute(
            secret: secret,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: channelBinding
        )
        return Fixture(secret: secret, phoneSpkiDer: phoneSpkiDer, confirmationCode: confirmationCode)
    }

    private static func confirmationPendingWindow(
        secret: Data,
        clock: ManualTestClock = ManualTestClock()
    ) -> (window: PairingWindow, token: PairingCandidateToken) {
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider,
            proofVerifier: SpyPairRequestVerifier(result: true)
        )
        window.open(secret: secret)
        let token = window.admitCandidate()!
        _ = window.candidateHellosCompleted(token)
        _ = window.submitPairRequest(token, proof: Data([9]))
        return (window, token)
    }

    private static func makeViewModel(
        displayName: String = "Pixel 8",
        model: String = "Google Pixel 8",
        fixture: Fixture? = nil,
        window: PairingWindow? = nil,
        token: PairingCandidateToken? = nil,
        sink: any PairingCandidateSink = FakePairingCandidateSink(),
        trustStore: TrustStore = TrustStore(keychainStore: InMemoryKeychainStore()),
        onPaired: (@Sendable () async -> Void)? = nil
    ) throws -> PairConfirmationViewModel {
        let fixture = try fixture ?? Self.loadFixture()
        let resolvedWindowAndToken: (window: PairingWindow, token: PairingCandidateToken)
        if let window, let token {
            resolvedWindowAndToken = (window, token)
        } else {
            resolvedWindowAndToken = Self.confirmationPendingWindow(secret: fixture.secret)
        }
        return PairConfirmationViewModel(
            displayNameBytes: Data(displayName.utf8),
            modelBytes: Data(model.utf8),
            confirmationCode: fixture.confirmationCode,
            handshakeSpkiDer: fixture.phoneSpkiDer,
            window: resolvedWindowAndToken.window,
            token: resolvedWindowAndToken.token,
            sink: sink,
            trustStore: trustStore,
            dateProvider: { Date(timeIntervalSince1970: 0) },
            onPaired: onPaired
        )
    }

    private static func grouped(_ code: String) -> String {
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<mid]) \(code[mid...])"
    }
}
