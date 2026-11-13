import Foundation
import Network
import Testing
import TandemTestSupport
@testable import TandemTransport

/// SPEC.md "Discovery TXT record": the Mac advertises `_tandem._tcp` with the bound listener port,
/// and republishes whenever the listener rebinds.
@Suite("ListenerBonjour")
struct ListenerBonjourTests {
    private static let fingerprint = Data(repeating: 0xAB, count: 32)

    private static func make(_ publisher: FakeBonjourPublisher, fingerprint: Data? = fingerprint) -> ListenerBonjour {
        ListenerBonjour(
            publisher: publisher,
            macSpkiFingerprint: { fingerprint },
            dateProvider: FixedDateProvider(clock: ManualTestClock()).provider,
            clock: ManualTestClock()
        )
    }

    @Test
    func appComposition_listenerStarted_bonjourPublishedWithBoundPort() async throws {
        let publisher = FakeBonjourPublisher()
        let bonjour = Self.make(publisher)

        await bonjour.listenerStarted(port: 50_123)

        let call = try #require(publisher.lastPublishCall)
        #expect(call.port == 50_123)
        #expect(Set(NWTXTRecord(call.txtRecord).dictionary.keys) == ["v", "id"])
    }

    @Test
    func appComposition_listenerRebound_bonjourRepublishedWithNewPort() async throws {
        let publisher = FakeBonjourPublisher()
        let bonjour = Self.make(publisher)

        await bonjour.listenerStarted(port: 50_123)
        await bonjour.listenerStarted(port: 50_456)

        #expect(publisher.publishCallCount == 2)
        #expect(try #require(publisher.lastPublishCall).port == 50_456)
    }

    @Test
    func appComposition_noIdentity_nothingPublished() async {
        let publisher = FakeBonjourPublisher()
        let bonjour = ListenerBonjour(
            publisher: publisher,
            macSpkiFingerprint: { nil },
            dateProvider: FixedDateProvider(clock: ManualTestClock()).provider,
            clock: ManualTestClock()
        )

        await bonjour.listenerStarted(port: 50_123)

        #expect(publisher.publishCallCount == 0)
    }
}
