import Foundation
import Testing
import TandemCrypto
@testable import TandemProtocol
@testable import TandemTransport

private actor SpyService: SessionService {
    private(set) var attachedSessions: [ObjectIdentifier] = []
    private(set) var detachCount = 0

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        attachedSessions.append(ObjectIdentifier(session as AnyObject))
    }

    func detach(peer: SpkiFingerprint) async {
        detachCount += 1
    }
}

/// E22-12 tdd (unit): a registered session attaches every feature service exactly once; its end
/// detaches them.
@Suite("SessionServiceHost")
struct SessionServiceHostTests {
    private static let peer: SpkiFingerprint = {
        // swiftlint:disable:next force_try
        try! SpkiFingerprint(bytes: Data(repeating: 0x21, count: SpkiFingerprint.byteCount))
    }()

    @Test
    func appComposition_sessionRegistered_allFeatureServicesAttachedOnce() async {
        let services = [SpyService(), SpyService(), SpyService()]
        let host = SessionServiceHost(services: services)
        let session = FakeTandemSession()

        await host.sessionRegistered(peer: Self.peer, session: session)
        await host.sessionRegistered(peer: Self.peer, session: session)

        for service in services {
            #expect(await service.attachedSessions.count == 1)
            #expect(await service.detachCount == 0)
        }
    }

    @Test
    func appComposition_sessionEnded_everyServiceDetached() async {
        let services = [SpyService(), SpyService()]
        let host = SessionServiceHost(services: services)
        let session = FakeTandemSession()

        await host.sessionRegistered(peer: Self.peer, session: session)
        await host.sessionEnded(peer: Self.peer, session: session)
        await host.sessionEnded(peer: Self.peer, session: session)

        for service in services {
            #expect(await service.detachCount == 1)
        }
    }

    @Test
    func appComposition_newSessionForSamePeer_detachesOldThenAttachesNew() async {
        let service = SpyService()
        let host = SessionServiceHost(services: [service])
        let older = FakeTandemSession()
        let newer = FakeTandemSession()

        await host.sessionRegistered(peer: Self.peer, session: older)
        await host.sessionRegistered(peer: Self.peer, session: newer)
        await host.sessionEnded(peer: Self.peer, session: older)

        #expect(await service.attachedSessions.count == 2)
        #expect(await service.detachCount == 1)
    }
}
