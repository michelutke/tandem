import Foundation
import Testing
import TandemTransport
@testable import TandemTestSupport

@Suite("InMemoryConnectionPair")
struct InMemoryConnectionPairTests {

    @Test
    func inMemoryPair_sendOnA_sameBytesReceivedOnB() async throws {
        let pair = InMemoryConnectionPair()
        try await pair.endA.send(Data("hello tandem".utf8))

        var iterator = pair.endB.receive().makeAsyncIterator()
        let received = try #require(try await iterator.next())

        #expect(received == Data("hello tandem".utf8))
    }

    @Test(.timeLimit(.minutes(1)))
    func inMemoryPair_bufferFull_sendSuspendsUntilPeerReceives() async throws {
        let capacity = 64 * 1024
        let pair = InMemoryConnectionPair(bufferCapacity: capacity)
        let payload = Data((0..<(1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })

        let sender = Task { try await pair.endA.send(payload) }
        // Until B reads, only one buffer's worth can be in flight.
        while await pair.captured(.aToB).count < capacity { await Task.yield() }
        for _ in 0..<100 { await Task.yield() }
        #expect(await pair.captured(.aToB).count == capacity)

        var received = Data()
        for try await chunk in pair.endB.receive() {
            #expect(chunk.count <= capacity)
            received.append(chunk)
            if received.count == payload.count { break }
        }
        try await sender.value

        #expect(received == payload)
    }

    @Test(.timeLimit(.minutes(1)))
    func inMemoryPair_cancelA_peerStateBecomesFailed() async throws {
        let pair = InMemoryConnectionPair()
        pair.endA.cancel()

        var states: [ConnectionState] = []
        for await state in pair.endB.state { states.append(state) }

        #expect(states.first == .ready)
        guard case .failed = states.last else {
            Issue.record("expected .failed, got \(states)")
            return
        }
        await #expect(throws: ConnectionFailure.self) {
            for try await _ in pair.endB.receive() {}
        }
    }

    @Test
    func inMemoryPair_capture_recordsBytesPerDirection() async throws {
        let pair = InMemoryConnectionPair()
        try await pair.endA.send(Data([1, 2, 3]))
        try await pair.endB.send(Data([9]))
        try await pair.inject(Data([4]), into: .aToB)

        #expect(await pair.captured(.aToB) == Data([1, 2, 3, 4]))
        #expect(await pair.captured(.bToA) == Data([9]))
    }

    @Test(.timeLimit(.minutes(1)))
    func inMemoryPair_closeA_peerReceiveFinishesAndStateClosed() async throws {
        let pair = InMemoryConnectionPair()
        try await pair.endA.send(Data([7]))
        await pair.endA.close()

        var received = Data()
        for try await chunk in pair.endB.receive() { received.append(chunk) }
        var states: [ConnectionState] = []
        for await state in pair.endB.state { states.append(state) }

        #expect(received == Data([7]))
        #expect(states == [.ready, .closed])
    }
}
