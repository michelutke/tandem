import CryptoKit
import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import TandemTestSupport
import TandemTransport
@testable import TandemPairing
@testable import TandemProtocol

/// The Mac's own pairing composition root (E14-09/E14-16), exercised end to end against a real
/// ``PairingWindow`` and a ``FakeTandemSession`` (never a real socket) -- the coverage gap the
/// E14-16 security review called out: every other test in this suite exercises one layer
/// (``PairingWindow``, ``PairingCandidateFlow``, ``PairConfirmationViewModel``) in isolation, but
/// none of them proves ``PairingCoordinator/drive(session:handshakeSpkiDer:token:)`` actually wires
/// them together correctly.
@Suite("PairingCoordinator")
struct PairingCoordinatorTests {

    @Test(.timeLimit(.minutes(1)))
    func drive_happyPath_pairAcceptedSentTrustCommittedAndSessionRegistered() async throws {
        let fixture = try Fixture.make()
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }

        let challenge = try await Self.waitForChallenge(session, timeout: 2)
        let proof = try PairingProof.compute(
            secret: fixture.coordinator.viewModel.currentPayload.secret,
            macSpkiDer: fixture.macSpkiDer,
            phoneSpkiDer: fixture.phoneSpkiDer,
            channelBinding: challenge
        )
        await session.inject(Self.pairRequestFrame(proof: proof))

        let viewModel = try await Self.waitForConfirmation(fixture, timeout: 2)
        await viewModel.pair()

        let registered = await Self.waitFor(timeout: 2) { await fixture.sessionRegistry.registeredFingerprints.count == 1 }
        #expect(registered)

        await session.close()
        await driveTask.value

        let sent = await session.sent
        #expect(sent.contains { if case .pairAccepted = $0.payload { return true } else { return false } })
        #expect(fixture.window.closedReason == .paired)
        let records = try fixture.trustStore.list()
        #expect(records.count == 1)
        #expect(records.first?.fingerprint == (try SpkiFingerprint.of(spkiDer: fixture.phoneSpkiDer)))

        let removed = await Self.waitFor(timeout: 2) { await fixture.sessionRegistry.registeredFingerprints.isEmpty }
        #expect(removed)
    }

    @Test(.timeLimit(.minutes(1)))
    func drive_badProof_pairRejectedPairingUnavailableAndAttemptBurned() async throws {
        let fixture = try Fixture.make()
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }

        _ = try await Self.waitForChallenge(session, timeout: 2)
        await session.inject(Self.pairRequestFrame(proof: Data(repeating: 0xFF, count: 32)))

        await driveTask.value

        let sent = await session.sent
        #expect(sent.contains { $0.payload == .pairRejected(Self.pairingUnavailable) })
        #expect(fixture.window.attemptsRemaining == 2)
        #expect(!fixture.window.candidateInFlight)
        #expect(try fixture.trustStore.list().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func drive_wrongPayload_pairRejectedAndAttemptBurned() async throws {
        let fixture = try Fixture.make()
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }

        _ = try await Self.waitForChallenge(session, timeout: 2)
        // A `PairAccepted` from the phone is never a legal payload at this point in the sequence.
        await session.inject(
            InboundFrame(channel: .control, seq: 2, ack: 0, payload: .pairAccepted(Tandem_V1_PairAccepted()))
        )

        await driveTask.value

        let sent = await session.sent
        #expect(sent.contains { $0.payload == .pairRejected(Self.pairingUnavailable) })
        #expect(fixture.window.attemptsRemaining == 2)
        #expect(!fixture.window.candidateInFlight)
    }

    @Test(.timeLimit(.minutes(1)))
    func drive_windowExpiresWhileConfirmationPending_dialogDismissedNoTrustCommitted() async throws {
        let fixture = try Fixture.make()
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }

        let challenge = try await Self.waitForChallenge(session, timeout: 2)
        let proof = try PairingProof.compute(
            secret: fixture.coordinator.viewModel.currentPayload.secret,
            macSpkiDer: fixture.macSpkiDer,
            phoneSpkiDer: fixture.phoneSpkiDer,
            channelBinding: challenge
        )
        await session.inject(Self.pairRequestFrame(proof: proof))
        let viewModel = try await Self.waitForConfirmation(fixture, timeout: 2)

        fixture.clock.advance(by: .seconds(120))
        await session.inject(InboundFrame(channel: .control, seq: 3, ack: 0, payload: .heartbeat(Tandem_V1_Heartbeat())))

        await driveTask.value

        #expect(fixture.window.closedReason == .expired)
        let resolved = await Self.waitFor(timeout: 2) { viewModel.isResolved }
        #expect(resolved)
        #expect(try fixture.trustStore.list().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func drive_staleCandidateAbandonedThenFreshCandidateAdmitted_freshCandidateUnaffected() async throws {
        let fixture = try Fixture.make()

        // `Fixture.make()` already admitted `fixture.token` (D-18: one candidate slot at a time) --
        // reuse it as the stale candidate, abandoned before ever calling `drive()` at all, exactly
        // `NWListenerFactory`'s own pre-Ready exit path (E14-16 finding #1).
        let staleToken = fixture.token
        await fixture.coordinator.candidateAbandoned(token: staleToken)
        #expect(!fixture.window.candidateInFlight)
        #expect(fixture.window.attemptsRemaining == 2)

        let freshToken = try #require(fixture.coordinator.window.admitCandidate())
        let freshSession = FakeTandemSession()
        let driveTask = Task {
            await fixture.coordinator.drive(
                session: freshSession,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: freshToken
            )
        }

        let challenge = try await Self.waitForChallenge(freshSession, timeout: 2)
        let proof = try PairingProof.compute(
            secret: fixture.coordinator.viewModel.currentPayload.secret,
            macSpkiDer: fixture.macSpkiDer,
            phoneSpkiDer: fixture.phoneSpkiDer,
            channelBinding: challenge
        )
        await freshSession.inject(Self.pairRequestFrame(proof: proof))
        _ = try await Self.waitForConfirmation(fixture, timeout: 2)

        // A delayed abandonment for the *stale* candidate arriving after the fresh one is already
        // pending confirmation must never burn the fresh candidate's attempt or evict its slot.
        await fixture.coordinator.candidateAbandoned(token: staleToken)

        #expect(fixture.window.isConfirmationPending)
        #expect(fixture.window.attemptsRemaining == 2)

        await freshSession.close()
        await driveTask.value
    }

    // MARK: - E14-16 finding #4: heartbeat race during `pair()`'s `PairAccepted` send

    @Test(.timeLimit(.minutes(1)))
    func drive_heartbeatBetweenOwnerAcceptedAndPairAccepted_noPairRejectedSent() async throws {
        let fixture = try Fixture.make()
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }

        let challenge = try await Self.waitForChallenge(session, timeout: 2)
        let proof = try PairingProof.compute(
            secret: fixture.coordinator.viewModel.currentPayload.secret,
            macSpkiDer: fixture.macSpkiDer,
            phoneSpkiDer: fixture.phoneSpkiDer,
            channelBinding: challenge
        )
        await session.inject(Self.pairRequestFrame(proof: proof))
        _ = try await Self.waitForConfirmation(fixture, timeout: 2)

        // Simulates `PairConfirmationViewModel.pair()` having already run its own
        // `window.ownerAccepted(token)` (its very first side effect) but not yet having reached
        // `sendPairAccepted`/`onResolved` -- a `Heartbeat` landing on this exact connection's own
        // frame loop in precisely that window must never be treated as a failure (E14-16 finding
        // #4), nor tear `drive()` down.
        #expect(fixture.window.ownerAccepted(fixture.token))
        await session.inject(InboundFrame(channel: .control, seq: 3, ack: 0, payload: .heartbeat(Tandem_V1_Heartbeat())))

        // Give the frame loop a moment to process the heartbeat before closing the session.
        try? await ContinuousClock().sleep(for: .milliseconds(20))
        await session.close()
        await driveTask.value

        let sent = await session.sent
        #expect(!sent.contains { if case .pairRejected = $0.payload { return true } else { return false } })
        #expect(fixture.window.closedReason == .paired)
    }

    @Test(.timeLimit(.minutes(1)))
    func drive_noPairRequestWithin10s_closesWithNoPairRejectedAndAttemptBurned() async throws {
        let fixture = try Fixture.make()
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.coordinator.drive(
                session: session,
                handshakeSpkiDer: fixture.phoneSpkiDer,
                token: fixture.token
            )
        }

        FileHandle.standardError.write("DBG1 before waitForChallenge\n".data(using: .utf8)!)
        _ = try await Self.waitForChallenge(session, timeout: 2)
        FileHandle.standardError.write("DBG2 after waitForChallenge\n".data(using: .utf8)!)
        // The active deadline watcher (E14-16 finding #5) is a `Task` racing this test's own
        // foreground code: `clock.advance(by:)` must not run until that `Task` has actually
        // reached its own `clock.sleep(for:)` call and parked, or its deadline would be computed
        // from a `now` that already reflects this advance, needing a second one that never comes
        // (`ManualTestClock.pendingSleeperCountForTesting`'s own documented idiom,
        // `ManualTestClockTests`).
        while fixture.clock.pendingSleeperCountForTesting < 1 {
            await Task.yield()
        }
        FileHandle.standardError.write("DBG3 sleeper parked, advancing\n".data(using: .utf8)!)
        fixture.clock.advance(by: .seconds(10))
        FileHandle.standardError.write("DBG4 advanced, awaiting driveTask\n".data(using: .utf8)!)

        await driveTask.value
        FileHandle.standardError.write("DBG5 driveTask done\n".data(using: .utf8)!)

        let sent = await session.sent
        #expect(!sent.contains { if case .pairRejected = $0.payload { return true } else { return false } })
        #expect(fixture.window.attemptsRemaining == 2)
        #expect(!fixture.window.candidateInFlight)
    }

    // MARK: - Fixture

    private struct Fixture {
        let coordinator: PairingCoordinator
        let window: PairingWindow
        let token: PairingCandidateToken
        let macSpkiDer: Data
        let phoneSpkiDer: Data
        let trustStore: TrustStore
        let sessionRegistry: SpyControlSessionRegistry
        let clock: ManualTestClock
        /// Per-fixture, never shared across tests -- `Testing` runs `@Suite` tests concurrently by
        /// default, so a `static` box here would let one test observe (or overwrite) another's
        /// `onConfirmationPending` callback.
        let confirmationBox: ConfirmationBox

        static func make() throws -> Fixture {
            let clock = ManualTestClock()
            let macSpkiDer = Self.makeValidSpkiDer()
            let phoneSpkiDer = Self.makeValidSpkiDer()
            let fingerprint = try SpkiFingerprint.of(spkiDer: macSpkiDer)
            let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
            let sessionRegistry = SpyControlSessionRegistry()
            let confirmationBox = ConfirmationBox()

            let coordinator = PairingCoordinator(
                fingerprint: fingerprint,
                macSpkiDerProvider: { macSpkiDer },
                port: 54321,
                name: "Test Mac",
                trustStore: trustStore,
                dateProvider: FixedDateProvider(clock: clock).provider,
                clock: clock,
                sessionRegistry: sessionRegistry,
                onConfirmationPending: { _, viewModel in
                    confirmationBox.set(viewModel)
                }
            )
            let token = try #require(coordinator.window.admitCandidate())

            return Fixture(
                coordinator: coordinator,
                window: coordinator.window,
                token: token,
                macSpkiDer: macSpkiDer,
                phoneSpkiDer: phoneSpkiDer,
                trustStore: trustStore,
                sessionRegistry: sessionRegistry,
                clock: clock,
                confirmationBox: confirmationBox
            )
        }

        /// A real, structurally valid uncompressed P-256 SPKI DER (matching
        /// `PeerAuthorizerTests.makeValidSpkiDer()`'s construction).
        static func makeValidSpkiDer() -> Data {
            let header = Data([
                0x30, 0x59, 0x30, 0x13,
                0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
                0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
                0x03, 0x42, 0x00
            ])
            let point = P256.Signing.PrivateKey().publicKey.x963Representation
            return header + point
        }
    }

    // MARK: - Harness

    private static let pairingUnavailable = Tandem_V1_PairRejected.with { $0.reason = .pairingUnavailable }

    private static func pairRequestFrame(proof: Data) -> InboundFrame {
        let request = Tandem_V1_PairRequest.with {
            $0.deviceInfo = Tandem_V1_DeviceInfo.with {
                $0.displayName = "Test Phone"
                $0.model = "Test Model"
            }
            $0.proof = proof
        }
        return InboundFrame(channel: .control, seq: 2, ack: 0, payload: .pairRequest(request))
    }

    private static func waitForChallenge(_ session: FakeTandemSession, timeout: TimeInterval) async throws -> Data {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            let sent = await session.sent
            for frame in sent {
                if case .pairChallenge(let message) = frame.payload {
                    return message.challenge
                }
            }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        struct TimedOut: Error {}
        throw TimedOut()
    }

    private static func waitForConfirmation(_ fixture: Fixture, timeout: TimeInterval) async throws -> PairConfirmationViewModel {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if let viewModel = fixture.confirmationBox.value {
                return viewModel
            }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        struct TimedOut: Error {}
        throw TimedOut()
    }

    private static func waitFor(timeout: TimeInterval, _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        return false
    }
}

/// Lock-protected single-slot box for the one ``PairConfirmationViewModel`` a test's
/// `onConfirmationPending` hook ever receives.
private final class ConfirmationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PairConfirmationViewModel?

    var value: PairConfirmationViewModel? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ viewModel: PairConfirmationViewModel) {
        lock.lock()
        stored = viewModel
        lock.unlock()
    }
}

/// ``ControlSessionRegistering`` spy: records every currently-registered fingerprint, mirroring
/// `TandemTransportTests`' own private copy (not visible from this package's test target).
private final class SpyControlSessionRegistry: ControlSessionRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var fingerprints: Set<SpkiFingerprint> = []

    var registeredFingerprints: Set<SpkiFingerprint> {
        lock.lock()
        defer { lock.unlock() }
        return fingerprints
    }

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        insert(spkiFingerprint)
    }

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        remove(spkiFingerprint)
    }

    private func insert(_ spkiFingerprint: SpkiFingerprint) {
        lock.lock()
        fingerprints.insert(spkiFingerprint)
        lock.unlock()
    }

    private func remove(_ spkiFingerprint: SpkiFingerprint) {
        lock.lock()
        fingerprints.remove(spkiFingerprint)
        lock.unlock()
    }
}
