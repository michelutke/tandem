import Foundation
import Testing
import TandemProtocol

@testable import TandemApp

@Suite("ConnectionStateRelay subscribers")
struct ConnectionStateRelaySubscribersTests {
    @Test
    func relay_terminatedSubscriber_isRemoved() async throws {
        let subscribers = Subscribers()
        var stream: AsyncStream<ConnectionStateMachine.ConnectionState>? = subscribers.makeStream()
        #expect(subscribers.subscriberCount == 1)

        stream = nil
        _ = stream

        #expect(subscribers.subscriberCount == 0)
    }
}
