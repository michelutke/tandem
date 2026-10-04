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

        host.sessionRegistered(peer: Self.peer, session: session)
        host.sessionRegistered(peer: Self.peer, session: session)
        await host.waitUntilIdle()

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

        host.sessionRegistered(peer: Self.peer, session: session)
        host.sessionEnded(peer: Self.peer, session: session)
        host.sessionEnded(peer: Self.peer, session: session)
        await host.waitUntilIdle()

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

        host.sessionRegistered(peer: Self.peer, session: older)
        host.sessionRegistered(peer: Self.peer, session: newer)
        host.sessionEnded(peer: Self.peer, session: older)
        await host.waitUntilIdle()

        #expect(await service.attachedSessions.count == 2)
        #expect(await service.detachCount == 1)
    }

    @Test
    func appComposition_endArrivesDuringAttach_serviceDetachedAfterwards() async {
        let service = SlowAttachService()
        let host = SessionServiceHost(services: [service])
        let session = FakeTandemSession()

        host.sessionRegistered(peer: Self.peer, session: session)
        await service.waitUntilAttachStarted()
        host.sessionEnded(peer: Self.peer, session: session)
        await service.finishAttach()
        await host.waitUntilIdle()

        #expect(await service.attachCount == 1)
        #expect(await service.detachCount == 1)
        #expect(await service.isAttached == false)
    }
}

private actor SlowAttachService: SessionService {
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    private var attachStarted: CheckedContinuation<Void, Never>?
    private var attachGate: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var isReleased = false

    var isAttached: Bool { attachCount > detachCount }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        hasStarted = true
        attachStarted?.resume()
        if !isReleased { await withCheckedContinuation { attachGate = $0 } }
        attachCount += 1
    }

    func detach(peer: SpkiFingerprint) async {
        detachCount += 1
    }

    func waitUntilAttachStarted() async {
        if !hasStarted { await withCheckedContinuation { attachStarted = $0 } }
    }

    func finishAttach() {
        isReleased = true
        attachGate?.resume()
    }
}
