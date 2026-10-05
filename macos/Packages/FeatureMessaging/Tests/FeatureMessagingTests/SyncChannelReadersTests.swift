import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import FeatureMessaging
@testable import TandemProtocol

struct SyncChannelReadersTests {
    // swiftlint:disable:next force_try
    private let peer = try! SpkiFingerprint(bytes: Data(repeating: 0xB2, count: SpkiFingerprint.byteCount))

    @Test
    func startSmsSyncReader_smsSyncResponseFrame_appliedToStore() async throws {
        let session = FakeTandemSession()
        let store = InMemorySmsStore()
        let client = SmsSyncClient(peer: peer, store: store, session: session)
        let reader = startSmsSyncReader(session: session, client: client)

        var thread = Tandem_V1_SmsThread()
        thread.threadID = 7
        var response = Tandem_V1_SmsSyncResponse()
        response.status = .ok
        response.threads = [thread]
        response.highWatermarkID = 5
        response.backfillComplete = true
        await session.inject(
            InboundFrame(channel: .sms, seq: 1, ack: 0, payload: .smsSyncResponse(response))
        )
        await session.close()
        await reader.value

        #expect(try await store.cursors(peer: peer)?.highWatermarkId == 5)
    }

    @Test
    func startContactsSyncReader_contactsSyncResponseFrame_appliedToStore() async throws {
        let session = FakeTandemSession()
        let store = InMemoryContactsStore()
        let client = ContactsSyncClient(peer: peer, session: session, store: store)
        let reader = startContactsSyncReader(session: session, client: client)

        var response = Tandem_V1_ContactsSyncResponse()
        response.status = .ok
        response.complete = true
        response.watermarkMs = 42
        await session.inject(
            InboundFrame(channel: .contacts, seq: 1, ack: 0, payload: .contactsSyncResponse(response))
        )
        await session.close()
        await reader.value

        #expect(try await store.watermarkMs(peer: peer) == 42)
    }
}
