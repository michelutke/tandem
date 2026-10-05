import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemProtocol
import TandemTransport
@testable import FeatureMirror

private func fingerprint(_ byte: UInt8) -> SpkiFingerprint {
    // swiftlint:disable:next force_try
    try! SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
}

@Suite("MirrorSessionService")
struct MirrorSessionServiceTests {
    @Test
    func mirrorSessionService_requestMediaTicket_sendsGrantOnControl() async throws {
        let clock = ManualTestClock()
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        let issuer = MediaTicketIssuer(
            table: MediaTicketTable(clock: clock), source: SystemMediaTicketSource(), dateProvider: dates.provider)
        let registry = MediaSessionRegistry(issuer: issuer)
        let service = MirrorSessionService(registry: registry)
        let session = FakeTandemSession()
        await service.attach(peer: fingerprint(0xA1), session: session)

        await session.inject(InboundFrame(
            channel: .control, seq: 0, ack: 0, payload: .requestMediaTicket(Tandem_V1_RequestMediaTicket())))

        var grant: Tandem_V1_MediaTicketGrant?
        for _ in 0..<20_000 where grant == nil {
            await Task.yield()
            if case .mediaTicketGrant(let value)? = await session.sent.first?.payload { grant = value }
        }
        #expect(grant?.ticket.count == 32)
        #expect(await session.sent.first?.channel == .control)
    }

    @Test
    func mirrorSessionService_detach_endsRegistryEntry() async throws {
        let clock = ManualTestClock()
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        let issuer = MediaTicketIssuer(
            table: MediaTicketTable(clock: clock), source: SystemMediaTicketSource(), dateProvider: dates.provider)
        let ended = EndedIDs()
        let registry = MediaSessionRegistry(issuer: issuer, onEnded: { ended.add($0) })
        let service = MirrorSessionService(registry: registry)
        let peer = fingerprint(0xA1)
        await service.attach(peer: peer, session: FakeTandemSession())

        await service.detach(peer: peer)

        #expect(ended.count == 1)
    }

    @Test
    func mirrorSessionService_detachOnePeer_reportsOnlyItsMediaSessionId() async throws {
        let clock = ManualTestClock()
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        let issuer = MediaTicketIssuer(
            table: MediaTicketTable(clock: clock), source: SystemMediaTicketSource(), dateProvider: dates.provider)
        let registry = MediaSessionRegistry(issuer: issuer)
        let events = EndedIDs()
        let service = MirrorSessionService(
            registry: registry, onSessionAttached: { id, _ in events.add(id) }, onSessionDetached: { events.add($0) })
        let peerA = fingerprint(0xA1)
        await service.attach(peer: peerA, session: FakeTandemSession())
        await service.attach(peer: fingerprint(0xB2), session: FakeTandemSession())

        await service.detach(peer: peerA)

        #expect(events.ids.count == 3)
        #expect(events.ids[2] == events.ids[0])
        #expect(events.ids[2] != events.ids[1])
    }
}

private final class EndedIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MediaSessionID] = []
    var ids: [MediaSessionID] { lock.withLock { storage } }
    var count: Int { lock.withLock { storage.count } }
    func add(_ id: MediaSessionID) { lock.withLock { storage.append(id) } }
}
