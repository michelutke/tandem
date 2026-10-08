import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import TandemTestSupport
import TandemTransport
@testable import TandemPairing
@testable import TandemProtocol

/// Manual pairing on the Mac (E73-04, ADR-008, SPEC § Manual pairing): the commit-then-reveal
/// sequence driven through ``PairingCoordinator`` against a real ``PairingWindow`` and a
/// ``FakeTandemSession``.
@Suite("ManualPairing")
struct ManualPairingCoordinatorTests {
    private static let noncePhone = Data(repeating: 0x11, count: 16)

    private struct Run {
        let fixture: PairingCoordinatorTests.Fixture
        let session: FakeTandemSession
        let driveTask: Task<Void, Never>
        let challenge: Data
    }

    private static func start(mode: PairingMode = .manual) async throws -> Run {
        let fixture = try PairingCoordinatorTests.Fixture.make(mode: mode)
        let session = FakeTandemSession()
        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }
        let challenge = try await PairingCoordinatorTests.waitForChallenge(session, timeout: 2)
        return Run(fixture: fixture, session: session, driveTask: driveTask, challenge: challenge)
    }

    private static func sasContext(_ run: Run) -> ManualPairingSas.Context {
        ManualPairingSas.Context(
            macSpkiDer: run.fixture.macSpkiDer, phoneSpkiDer: run.fixture.phoneSpkiDer, channelBinding: run.challenge
        )
    }

    private static func commitmentHash(_ run: Run, nonce: Data = noncePhone) throws -> Data {
        try ManualPairingSas.commitment(role: .phone, nonce: nonce, context: sasContext(run))
    }

    private static func commitmentFrame(_ hash: Data) -> InboundFrame {
        InboundFrame(
            channel: .control, seq: 2, ack: 0,
            payload: .commitment(Tandem_V1_Commitment.with { $0.hash = hash })
        )
    }

    private static func revealFrame(_ nonce: Data) -> InboundFrame {
        InboundFrame(
            channel: .control, seq: 3, ack: 0,
            payload: .reveal(Tandem_V1_Reveal.with { $0.nonce = nonce })
        )
    }

    private static func macPayloads(_ run: Run) async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await run.session.sent.compactMap { $0.payload }
    }

    private static func macNonce(_ run: Run) async -> Data? {
        for payload in await macPayloads(run) {
            if case .reveal(let message) = payload { return message.nonce }
        }
        return nil
    }

    private static func completeHandshake(_ run: Run) async throws -> PairConfirmationViewModel {
        await run.session.inject(commitmentFrame(try commitmentHash(run)))
        let committed = await PairingCoordinatorTests.waitFor(timeout: 2) {
            await macPayloads(run).contains { if case .commitment = $0 { return true } else { return false } }
        }
        #expect(committed)
        await run.session.inject(revealFrame(noncePhone))
        return try await PairingCoordinatorTests.waitForConfirmation(run.fixture, timeout: 2)
    }

    private static func assertAbortedWithoutPinning(_ run: Run, attemptsRemaining: Int = 2) async throws {
        await run.driveTask.value
        let rejected = await macPayloads(run).contains {
            $0 == .pairRejected(PairingCoordinatorTests.pairingUnavailable)
        }
        #expect(rejected)
        #expect(try run.fixture.trustStore.list().isEmpty)
        #expect(run.fixture.window.attemptsRemaining == attemptsRemaining)
        #expect(!run.fixture.window.isConfirmationPending)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_userConfirmsMatchingSas_pinsExactlyOnePeerRecord() async throws {
        let run = try await Self.start()
        let viewModel = try await Self.completeHandshake(run)
        let nonceMac = try #require(await Self.macNonce(run))
        let sas = try ManualPairingSas.sas(
            noncePhone: Self.noncePhone, nonceMac: nonceMac, context: Self.sasContext(run)
        )
        #expect(viewModel.bodyText.contains("\(sas.prefix(3)) \(sas.suffix(3))"))
        #expect(try run.fixture.trustStore.list().isEmpty)

        await viewModel.pair()

        let payloads = await Self.macPayloads(run)
        #expect(payloads.contains(.manualPairResult(Tandem_V1_ManualPairResult.with { $0.accepted = true })))
        #expect(!payloads.contains { if case .pairAccepted = $0 { return true } else { return false } })
        let records = try run.fixture.trustStore.list()
        #expect(records.count == 1)
        #expect(records.first?.fingerprint == (try SpkiFingerprint.of(spkiDer: run.fixture.phoneSpkiDer)))
        #expect(run.fixture.window.closedReason == .paired)
        await run.session.close()
        await run.driveTask.value
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_userReportsMismatch_abortsWithoutPinningAndClosesWindow() async throws {
        let run = try await Self.start()
        let viewModel = try await Self.completeHandshake(run)

        await viewModel.dontPair()

        await run.driveTask.value
        let payloads = await Self.macPayloads(run)
        #expect(payloads.contains(.pairRejected(Tandem_V1_PairRejected.with { $0.reason = .rejectedByOwner })))
        #expect(!payloads.contains { if case .manualPairResult = $0 { return true } else { return false } })
        #expect(try run.fixture.trustStore.list().isEmpty)
        #expect(run.fixture.window.closedReason == .declined)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_revealBeforePeerCommitment_abortsWithoutPinning() async throws {
        let run = try await Self.start()
        await run.session.inject(Self.revealFrame(Self.noncePhone))
        try await Self.assertAbortedWithoutPinning(run)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_revealMismatchesCommitment_abortsWithoutPinning() async throws {
        let run = try await Self.start()
        await run.session.inject(Self.commitmentFrame(try Self.commitmentHash(run)))
        _ = await PairingCoordinatorTests.waitFor(timeout: 2) { await Self.macPayloads(run).count >= 2 }
        await run.session.inject(Self.revealFrame(Data(repeating: 0x22, count: 16)))
        try await Self.assertAbortedWithoutPinning(run)
        #expect(await Self.macNonce(run) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairingVerifier_fingerprintPrefixMatchOnly_rejected() async throws {
        let run = try await Self.start()
        let macFingerprint = try SpkiFingerprint.of(spkiDer: run.fixture.macSpkiDer)
        let prefixOnly = Data(macFingerprint.bytes.prefix(16))
        await run.session.inject(Self.commitmentFrame(try Self.commitmentHash(run)))
        _ = await PairingCoordinatorTests.waitFor(timeout: 2) { await Self.macPayloads(run).count >= 2 }
        await run.session.inject(Self.revealFrame(prefixOnly))
        try await Self.assertAbortedWithoutPinning(run)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_commitmentWithWrongLength_abortsWithoutPinning() async throws {
        let run = try await Self.start()
        await run.session.inject(Self.commitmentFrame(Data(repeating: 0xAB, count: 31)))
        try await Self.assertAbortedWithoutPinning(run)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_duplicateCommitment_abortsWithoutPinning() async throws {
        let run = try await Self.start()
        let hash = try Self.commitmentHash(run)
        await run.session.inject(Self.commitmentFrame(hash))
        await run.session.inject(Self.commitmentFrame(hash))
        try await Self.assertAbortedWithoutPinning(run)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_qrPairRequestOnManualWindow_abortsAndBurnsOneAttempt() async throws {
        let run = try await Self.start()
        await run.session.inject(PairingCoordinatorTests.pairRequestFrame(proof: Data(repeating: 0, count: 32)))
        try await Self.assertAbortedWithoutPinning(run)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_commitmentOnQrWindow_abortsAndBurnsOneAttempt() async throws {
        let run = try await Self.start(mode: .qrCode)
        await run.session.inject(Self.commitmentFrame(Data(repeating: 0xAB, count: 32)))
        try await Self.assertAbortedWithoutPinning(run)
    }

    @Test(.timeLimit(.minutes(1)))
    func manualPairing_secondRevealAfterSas_abortsWithoutPinning() async throws {
        let run = try await Self.start()
        _ = try await Self.completeHandshake(run)
        await run.session.inject(Self.revealFrame(Self.noncePhone))
        await run.driveTask.value
        #expect(try run.fixture.trustStore.list().isEmpty)
        #expect(!run.fixture.window.isConfirmationPending)
    }
}

@Suite("ManualPairingWindow")
struct ManualPairingWindowTests {
    private static func makeWindow() -> PairingWindow {
        PairingWindow(
            dateProvider: FixedDateProvider(clock: ManualTestClock()).provider,
            proofVerifier: SpyPairRequestVerifier(result: true)
        )
    }

    @Test
    func manualWindow_opened_modeIsManualAndQrOpenResetsIt() {
        let window = Self.makeWindow()
        window.openManual()
        #expect(window.mode == .manual)
        window.open(secret: Data(repeating: 1, count: 16))
        #expect(window.mode == .qrCode)
    }

    @Test
    func manualWindow_validQrProofSubmitted_rejectedAndBurnsAttemptWithoutVerifying() throws {
        let verifier = SpyPairRequestVerifier(result: true)
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: ManualTestClock()).provider, proofVerifier: verifier
        )
        window.openManual()
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)

        #expect(window.submitPairRequest(token, proof: Data(count: 32)) == .rejected)
        #expect(verifier.callCount == 0)
        #expect(window.attemptsRemaining == 2)
    }

    @Test
    func manualWindow_commitmentAfterTenSecondDeadline_notAccepted() throws {
        let clock = ManualTestClock()
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: clock).provider, proofVerifier: SpyPairRequestVerifier(result: true)
        )
        window.openManual()
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)
        clock.advance(by: .seconds(11))

        #expect(!window.manualCommitmentReceived(token))
        #expect(window.attemptsRemaining == 2)
    }

    @Test
    func manualWindow_revealWithoutCommitment_notVerified() throws {
        let window = Self.makeWindow()
        window.openManual()
        let token = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(token)

        #expect(!window.manualRevealVerified(token))
    }
}
