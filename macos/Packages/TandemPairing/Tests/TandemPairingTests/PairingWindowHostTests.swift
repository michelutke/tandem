import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import TandemTestSupport
import TandemTransport
@testable import TandemPairing
@testable import TandemProtocol

/// The production "Add phone" composition (E22-14): a user-opened, time-limited, single-use pairing
/// window fronted by one long-lived ``PairingWindowHost`` the listener is wired against once.
@Suite("MacPairingComposition")
struct PairingWindowHostTests {
    struct Fixture {
        let host: PairingWindowHost
        let clock: ManualTestClock
        let macSpkiDer: Data
        let phoneSpkiDer: Data
        let trustStore: TrustStore
        let sessionRegistry: SpyControlSessionRegistry
        let confirmationBox: ConfirmationBox

        static func make() throws -> Fixture {
            let clock = ManualTestClock()
            let macSpkiDer = PairingCoordinatorTests.Fixture.makeValidSpkiDer()
            let fingerprint = try SpkiFingerprint.of(spkiDer: macSpkiDer)
            let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
            let sessionRegistry = SpyControlSessionRegistry()
            let confirmationBox = ConfirmationBox()
            let host = PairingWindowHost {
                PairingCoordinator(
                    fingerprint: fingerprint,
                    macSpkiDerProvider: { macSpkiDer },
                    port: 54321,
                    name: "Test Mac",
                    trustStore: trustStore,
                    dateProvider: FixedDateProvider(clock: clock).provider,
                    clock: clock,
                    sessionRegistry: sessionRegistry,
                    regeneratesOnExpiry: false,
                    onConfirmationPending: { _, viewModel in confirmationBox.set(viewModel) }
                )
            }
            return Fixture(
                host: host,
                clock: clock,
                macSpkiDer: macSpkiDer,
                phoneSpkiDer: PairingCoordinatorTests.Fixture.makeValidSpkiDer(),
                trustStore: trustStore,
                sessionRegistry: sessionRegistry,
                confirmationBox: confirmationBox
            )
        }
    }

    @Test
    func macPairingComposition_beforeUserOpens_windowClosedAndNoCandidateAdmitted() throws {
        let fixture = try Fixture.make()

        #expect(!fixture.host.isOpen)
        #expect(fixture.host.admitCandidate() == nil)
    }

    @Test
    func macPairingComposition_userOpensWindow_inviteShownAndSecretSingleUse() throws {
        let fixture = try Fixture.make()

        let first = try fixture.host.open()
        let firstUri = first.viewModel.currentPayload.uri
        let firstSecret = first.viewModel.currentPayload.secret

        #expect(fixture.host.isOpen)
        #expect(firstUri.hasPrefix("tandem://"))

        let second = try fixture.host.open()

        #expect(second.viewModel.currentPayload.secret != firstSecret)
        #expect(!first.window.isOpen)
        #expect(fixture.host.isOpen)
    }

    @Test(.timeLimit(.minutes(1)))
    func macPairingComposition_confirmedCodes_commitsPinAndClosesWindow() async throws {
        let fixture = try Fixture.make()
        let coordinator = try fixture.host.open()
        let token = try #require(fixture.host.admitCandidate())
        let session = FakeTandemSession()

        let driveTask = Task {
            await fixture.host.drive(session: session, handshakeSpkiDer: fixture.phoneSpkiDer, token: token)
        }
        let challenge = try await PairingCoordinatorTests.waitForChallenge(session, timeout: 2)
        let proof = try PairingProof.compute(
            secret: coordinator.viewModel.currentPayload.secret,
            macSpkiDer: fixture.macSpkiDer,
            phoneSpkiDer: fixture.phoneSpkiDer,
            channelBinding: challenge
        )
        await session.inject(PairingCoordinatorTests.pairRequestFrame(proof: proof))
        let viewModel = try await Self.waitForConfirmation(fixture.confirmationBox)

        #expect(try fixture.trustStore.list().isEmpty)
        await viewModel.pair()
        await session.close()
        await driveTask.value

        #expect(!fixture.host.isOpen)
        #expect(coordinator.window.closedReason == .paired)
        let records = try fixture.trustStore.list()
        #expect(records.map(\.fingerprint) == [try SpkiFingerprint.of(spkiDer: fixture.phoneSpkiDer)])
    }

    @Test
    func macPairingComposition_windowTimesOut_closesAndRefusesCandidates() throws {
        let fixture = try Fixture.make()
        let coordinator = try fixture.host.open()

        fixture.clock.advance(by: .seconds(PairingWindow.defaultExpiry + 1))

        #expect(!fixture.host.isOpen)
        #expect(fixture.host.admitCandidate() == nil)
        #expect(coordinator.window.closedReason == .expired)
        #expect(coordinator.viewModel.remainingSeconds == 0)
        coordinator.viewModel.tick()
        #expect(!fixture.host.isOpen)
    }

    @Test
    func macPairingComposition_ownerCancels_closesAndRefusesCandidates() throws {
        let fixture = try Fixture.make()
        let coordinator = try fixture.host.open()

        fixture.host.cancel()

        #expect(!fixture.host.isOpen)
        #expect(fixture.host.admitCandidate() == nil)
        #expect(coordinator.window.closedReason == .cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func macPairingComposition_driveWhileClosed_closesSessionWithoutTrust() async throws {
        let fixture = try Fixture.make()
        let coordinator = try fixture.host.open()
        let token = try #require(fixture.host.admitCandidate())
        fixture.host.cancel()
        let session = FakeTandemSession()

        await fixture.host.drive(session: session, handshakeSpkiDer: fixture.phoneSpkiDer, token: token)

        #expect(try fixture.trustStore.list().isEmpty)
        #expect(coordinator.window.closedReason == .cancelled)
        #expect(await session.sent.isEmpty)
    }

    private static func waitForConfirmation(_ box: ConfirmationBox) async throws -> PairConfirmationViewModel {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if let viewModel = box.value { return viewModel }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        struct TimedOut: Error {}
        throw TimedOut()
    }
}
