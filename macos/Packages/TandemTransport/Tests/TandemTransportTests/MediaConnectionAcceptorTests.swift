import Foundation
import Synchronization
import Testing
import TandemCrypto
import TandemProtocol
import TandemTestSupport
@testable import TandemTransport

@Suite("MediaConnectionAcceptor")
struct MediaConnectionAcceptorTests {
    private let peer: MediaConnectionPeer

    init() throws {
        peer = .trusted(try SpkiFingerprint(bytes: Data(repeating: 7, count: 32)))
    }

    @Test
    func mediaAcceptor_firstFrameNotMediaHello_closesWithoutReadingNextFrame() async {
        let validator = OneShotTicketValidator()
        let acceptor = Self.makeAcceptor(validator)
        let connection = ScriptedConnection(chunks: [
            MediaFrameFixtures.versionHelloFrame,
            MediaFrameFixtures.validHelloFrame
        ])

        let binding = await acceptor.accept(connection: connection, peer: peer)

        #expect(binding == nil)
        #expect(connection.pulls == 1)
        #expect(connection.cancelled)
        #expect(validator.callCount == 0)
        #expect(await Self.firstEvents(acceptor, count: 1) == [.closed(.malformedFrame)])
    }

    @Test
    func mediaAcceptor_validatorRejects_emitsTicketRejectedEventNotHandshakeFailure() async {
        let validator = OneShotTicketValidator(ticket: Data(repeating: 9, count: 32))
        let acceptor = Self.makeAcceptor(validator)
        let rejected = ScriptedConnection(chunks: [MediaFrameFixtures.validHelloFrame])
        let sentinel = ScriptedConnection(chunks: [MediaFrameFixtures.validHelloFrame])

        let binding = await acceptor.accept(connection: rejected, peer: peer)
        _ = await acceptor.accept(connection: sentinel, peer: .pairingCandidate)

        #expect(binding == nil)
        #expect(rejected.cancelled)
        #expect(await Self.firstEvents(acceptor, count: 2) == [.ticketRejected(.reused), .closed(.malformedFrame)])
    }

    @Test
    func mediaAcceptor_pairingCandidateSendsMediaHello_closedWithoutValidatorCall() async {
        let validator = OneShotTicketValidator()
        let acceptor = Self.makeAcceptor(validator)
        let connection = ScriptedConnection(chunks: [MediaFrameFixtures.validHelloFrame])

        let binding = await acceptor.accept(connection: connection, peer: .pairingCandidate)

        #expect(binding == nil)
        #expect(connection.cancelled)
        #expect(validator.callCount == 0)
        #expect(await Self.firstEvents(acceptor, count: 1) == [.closed(.malformedFrame)])
    }

    @Test
    func mediaAcceptor_zeroLengthFirstFrame_closesMalformedWithoutValidatorCall() async {
        let validator = OneShotTicketValidator()
        let acceptor = Self.makeAcceptor(validator)
        let connection = ScriptedConnection(chunks: [MediaFrameFixtures.lengthPrefixed(Data())])

        let binding = await acceptor.accept(connection: connection, peer: peer)

        #expect(binding == nil)
        #expect(validator.callCount == 0)
        #expect(await Self.firstEvents(acceptor, count: 1) == [.closed(.malformedFrame)])
    }

    @Test
    func mediaAcceptor_emptyTicketField_reachesValidatorAsMissing() async {
        let validator = OneShotTicketValidator()
        let acceptor = Self.makeAcceptor(validator)
        let connection = ScriptedConnection(chunks: [MediaFrameFixtures.mediaHelloFrame(ticket: Data())])

        let binding = await acceptor.accept(connection: connection, peer: peer)

        #expect(binding == nil)
        #expect(validator.callCount == 1)
        #expect(await Self.firstEvents(acceptor, count: 1) == [.ticketRejected(.missing)])
    }

    @Test
    func mediaAcceptor_noMediaHelloWithin5s_closesProtocolTimeout() async throws {
        let validator = OneShotTicketValidator()
        let clock = ManualTestClock()
        let acceptor = MediaConnectionAcceptor(validator: validator, clock: clock, onBound: { _ in })
        let pair = InMemoryConnectionPair()
        let finished = Mutex(false)

        let task = Task {
            let binding = await acceptor.accept(connection: pair.endA, peer: peer)
            finished.withLock { $0 = true }
            return binding
        }
        while !finished.withLock({ $0 }) {
            clock.advance(by: MediaConnectionAcceptor.helloDeadline)
            await Task.yield()
        }

        #expect(await task.value == nil)
        #expect(validator.callCount == 0)
        #expect(await Self.firstEvents(acceptor, count: 1) == [.closed(.protocolTimeout)])
    }

    @Test
    func mediaAcceptor_validTicket_bindsSessionAndReplaysBytesSentAfterHello() async throws {
        let validator = OneShotTicketValidator()
        let acceptor = Self.makeAcceptor(validator)
        let trailing = Data([1, 2, 3])
        let connection = ScriptedConnection(chunks: [
            MediaFrameFixtures.validHelloFrame + trailing
        ])

        let binding = try #require(await acceptor.accept(connection: connection, peer: peer))

        #expect(binding.sessionID == validator.sessionID)
        var iterator = binding.connection.receive().makeAsyncIterator()
        #expect(try await iterator.next() == trailing)
        #expect(await Self.firstEvents(acceptor, count: 1) == [.bound(validator.sessionID)])
    }

    private static func makeAcceptor(_ validator: any MediaTicketValidating) -> MediaConnectionAcceptor {
        MediaConnectionAcceptor(validator: validator, clock: ManualTestClock(), onBound: { _ in })
    }

    private static func firstEvents(_ acceptor: MediaConnectionAcceptor, count: Int) async -> [MediaAcceptorEvent] {
        var events: [MediaAcceptorEvent] = []
        for await event in acceptor.events {
            events.append(event)
            if events.count == count { break }
        }
        return events
    }
}
