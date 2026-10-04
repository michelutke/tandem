import Foundation
import Testing
import TandemCrypto
@testable import TandemTestSupport
import TandemTransport
@testable import TandemPairing
@testable import TandemProtocol

@Suite("PairingPresenterSupport")
struct PairingPresenterSupportTests {
    @Test(arguments: [PairingWindowClosedReason.paired, .cancelled, .expired, .declined])
    func autoClose_terminalReason_closesWindow(reason: PairingWindowClosedReason) {
        #expect(PairingWindowAutoClose.shouldClose(closedReason: reason))
    }

    @Test
    func autoClose_attemptsExhausted_keepsWindowOpen() {
        #expect(!PairingWindowAutoClose.shouldClose(closedReason: .attemptsExhausted))
    }

    @Test
    func autoClose_stillOpen_keepsWindowOpen() {
        #expect(!PairingWindowAutoClose.shouldClose(closedReason: nil))
    }

    @Test
    func listenerPortSource_listenerReplaced_readsCurrentPort() {
        let source = ListenerPortSource()
        #expect(source.port == nil)

        source.listenerReplaced(portProvider: { 1111 })
        #expect(source.port == 1111)

        source.listenerReplaced(portProvider: { 2222 })
        #expect(source.port == 2222)
    }

    @Test
    func windowGeneration_nextWindow_invalidatesPreviousToken() {
        let generation = PairingWindowGeneration()
        let first = generation.next()
        #expect(generation.isCurrent(first))

        let second = generation.next()

        #expect(!generation.isCurrent(first))
        #expect(generation.isCurrent(second))
    }

    @Test(.timeLimit(.minutes(1)))
    func ownerClose_confirmationPending_sendsRejectedByOwnerInsteadOfCancel() async throws {
        let fixture = try PairingWindowHostTests.Fixture.make()
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

        await PairingOwnerClose.handle(pending: viewModel, host: fixture.host)
        await driveTask.value

        let sent = await session.sent
        #expect(sent.contains { $0.payload == .pairRejected(Self.rejectedByOwner) })
        #expect(viewModel.isResolved)
        #expect(coordinator.window.closedReason == .declined)
        #expect(try fixture.trustStore.list().isEmpty)
    }

    @Test
    func ownerClose_noConfirmationPending_cancelsWindow() async throws {
        let fixture = try PairingWindowHostTests.Fixture.make()
        let coordinator = try fixture.host.open()

        await PairingOwnerClose.handle(pending: nil, host: fixture.host)

        #expect(coordinator.window.closedReason == .cancelled)
    }

    private static var rejectedByOwner: Tandem_V1_PairRejected {
        var message = Tandem_V1_PairRejected()
        message.reason = .rejectedByOwner
        return message
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
