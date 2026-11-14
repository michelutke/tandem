import Foundation
import Testing
import TandemCrypto
@testable import TandemProtocol

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

    @Test
    func relay_failedPeerUnpaired_newStreamDoesNotReplayFailure() async throws {
        let relay = ConnectionStateRelay(isolatesFailuresByPeer: true)
        let phone = try SpkiFingerprint(bytes: Data(repeating: 0x0A, count: SpkiFingerprint.byteCount))
        let failing = FakeTandemSession()
        await relay.attach(failing, peer: phone)
        await failing.emit(.failed(.versionMismatch))
        var replayed = relay.makeStream().makeAsyncIterator()
        #expect(await replayed.next() == .failed(.versionMismatch))

        await relay.forgetFailureIfUnpaired { _ in false }
        let late = relay.makeStream()
        await failing.emit(.ready)
        var iterator = late.makeAsyncIterator()

        #expect(await iterator.next() == .ready)
    }

    @Test
    func relay_downstreamRelay_bothSeeEveryStateOfOneSession() async throws {
        let relay = ConnectionStateRelay()
        let banner = ConnectionStateRelay(isolatesFailuresByPeer: true)
        let phone = try SpkiFingerprint(bytes: Data(repeating: 0x0A, count: SpkiFingerprint.byteCount))
        var menuStates = relay.makeStream().makeAsyncIterator()
        var bannerStates = banner.makeStream().makeAsyncIterator()
        let session = FakeTandemSession()
        await relay.attach(session, peer: phone, downstream: banner)

        await session.emit(.helloExchange)
        await session.emit(.ready)

        #expect(await menuStates.next() == .helloExchange)
        #expect(await menuStates.next() == .ready)
        #expect(await bannerStates.next() == .helloExchange)
        #expect(await bannerStates.next() == .ready)
    }
}
