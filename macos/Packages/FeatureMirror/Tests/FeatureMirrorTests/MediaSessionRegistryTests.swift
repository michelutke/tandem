import Foundation
import Synchronization
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

private final class SpyConnection: ByteStreamConnection, Sendable {
    private let cancelledFlag = Mutex(false)

    var cancelled: Bool { cancelledFlag.withLock { $0 } }

    func send(_ data: Data) async throws {}
    func receive() -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish() } }
    var state: AsyncStream<ConnectionState> { AsyncStream { $0.finish() } }
    func cancel() { cancelledFlag.withLock { $0 = true } }
}

private final class SequentialSource: MediaTicketSource {
    private let next = Mutex<UInt8>(1)

    func generateTicket() -> Data {
        let value = next.withLock { current -> UInt8 in
            defer { current += 1 }
            return current
        }
        return Data(repeating: value, count: 32)
    }
}

private struct Harness {
    let clock = ManualTestClock()
    let table: MediaTicketTable<ManualTestClock>
    let validator: MediaTicketValidator<ManualTestClock>
    let registry: MediaSessionRegistry<ManualTestClock>
    let session = FakeTandemSession()
    let id = MediaSessionID(rawValue: UUID())
    let peer = fingerprint(0xA1)

    init() async {
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        table = MediaTicketTable(clock: clock)
        let issuer = MediaTicketIssuer(table: table, source: SequentialSource(), dateProvider: dates.provider)
        validator = MediaTicketValidator(table: table)
        registry = MediaSessionRegistry(issuer: issuer)
        await registry.register(states: session.state, id: id, peer: peer)
    }

    func bindMedia(presentedBy presenter: SpkiFingerprint? = nil) async -> SpyConnection {
        let connection = SpyConnection()
        await registry.bind(
            connection, to: id, mirrorSessionId: Data(repeating: 0x5C, count: 16), presentedBy: presenter ?? peer
        )
        return connection
    }

    func validationError(_ ticket: Data, peer presenter: SpkiFingerprint) -> MediaTicketError? {
        do {
            _ = try validator.validate(ticket: ticket, presentingSpki: presenter)
            return nil
        } catch {
            return error
        }
    }
}

private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<10_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

@Suite("MediaSessionRegistry")
struct MediaSessionRegistryTests {
    @Test
    func mediaRegistry_controlSessionDead_closesBoundMediaConnectionWithin1s() async {
        let harness = await Harness()
        _ = await harness.registry.requestTicket(for: harness.id)
        let media = await harness.bindMedia()

        await harness.session.emit(.dead)
        harness.clock.advance(by: .seconds(1))

        #expect(await eventually { media.cancelled })
        #expect(await harness.registry.hasActiveMedia(for: harness.id) == false)
    }

    @Test
    func mediaRegistry_controlSessionClosed_revokesOutstandingTickets() async throws {
        let harness = await Harness()
        let issued = try #require(await harness.registry.requestTicket(for: harness.id))

        await harness.session.close()

        #expect(await eventually { harness.validationError(issued.ticket, peer: harness.peer) == .revoked })
    }

    @Test
    func mediaRegistry_newTicketRequestedWhileActive_closesPriorBeforeIssuing() async throws {
        let harness = await Harness()
        let first = try #require(await harness.registry.requestTicket(for: harness.id))
        let media = await harness.bindMedia()

        let second = await harness.registry.requestTicket(for: harness.id)

        #expect(media.cancelled)
        #expect(second != nil)
        #expect(second?.ticket != first.ticket)
        #expect(await harness.registry.hasActiveMedia(for: harness.id) == false)
    }

    @Test
    func mediaRegistry_perControlSession_atMostOneOpenMediaConnection() async {
        let harness = await Harness()
        _ = await harness.registry.requestTicket(for: harness.id)
        let first = await harness.bindMedia()
        let second = await harness.bindMedia()

        #expect(first.cancelled == false)
        #expect(second.cancelled)
        #expect(await harness.registry.hasActiveMedia(for: harness.id))
    }

    @Test
    func mediaRegistry_mediaFromDifferentSpkiThanControlPeer_rejected() async throws {
        let harness = await Harness()
        let issued = try #require(await harness.registry.requestTicket(for: harness.id))
        let stranger = fingerprint(0xB2)

        #expect(harness.validationError(issued.ticket, peer: stranger) == .peerMismatch)
        #expect(harness.validationError(issued.ticket, peer: harness.peer) == .consumed)

        let media = await harness.bindMedia(presentedBy: stranger)
        #expect(media.cancelled)
        #expect(await harness.registry.hasActiveMedia(for: harness.id) == false)
    }

    @Test
    func mediaRegistry_requestTicketForEndedSession_returnsNil() async {
        let harness = await Harness()
        await harness.session.close()
        #expect(await eventually { await harness.registry.requestTicket(for: harness.id) == nil })
    }
}
