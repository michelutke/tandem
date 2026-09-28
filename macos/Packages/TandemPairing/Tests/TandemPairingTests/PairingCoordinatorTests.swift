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

        let registered = await Self.waitFor(timeout: 2) {
            await fixture.sessionRegistry.registeredFingerprints.count == 1
        }
        #expect(registered)

        await session.close()
        await driveTask.value

        let sent = await session.sent
        #expect(sent.contains { if case .pairAccepted = $0.payload { return true } else { return false } })
        #expect(fixture.window.closedReason == .paired)
        let records = try fixture.trustStore.list()
        #expect(records.count == 1)
        #expect(records.first?.fingerprint == (try SpkiFingerprint.of(spkiDer: fixture.phoneSpkiDer)))

        let removed = await Self.waitFor(timeout: 2) {
            await fixture.sessionRegistry.registeredFingerprints.isEmpty
        }
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
        await session.inject(
            InboundFrame(channel: .control, seq: 3, ack: 0, payload: .heartbeat(Tandem_V1_Heartbeat()))
        )

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
        await session.inject(
            InboundFrame(channel: .control, seq: 3, ack: 0, payload: .heartbeat(Tandem_V1_Heartbeat()))
        )

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

        _ = try await Self.waitForChallenge(session, timeout: 2)
        // The active deadline watcher (E14-16 finding #5) is a `Task` racing this test's own
        // foreground code: `clock.advance(by:)` must not run until that `Task` has actually
        // reached its own `clock.sleep(for:)` call and parked, or its deadline would be computed
        // from a `now` that already reflects this advance, needing a second one that never comes
        // (`ManualTestClock.pendingSleeperCountForTesting`'s own documented idiom,
        // `ManualTestClockTests`). Bounded via `waitFor` (real wall-clock timeout, matching every
        // other polling wait in this file) rather than an unbounded `Task.yield()` loop: if the
        // watcher never parks, this must fail fast with a clear assertion instead of hanging past
        // `.timeLimit` (a `while` loop with no suspension point that checks `Task.isCancelled`
        // ignores that trait's cancellation entirely).
        let parked = await Self.waitFor(timeout: 2) { fixture.clock.pendingSleeperCountForTesting >= 1 }
        #expect(parked, "the request-deadline watcher never parked on the clock")
        fixture.clock.advance(by: .seconds(10))

        await driveTask.value

        let sent = await session.sent
        #expect(!sent.contains { if case .pairRejected = $0.payload { return true } else { return false } })
        #expect(fixture.window.attemptsRemaining == 2)
        #expect(!fixture.window.candidateInFlight)
    }

}
