import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import FeatureMessaging
@testable import TandemProtocol

private extension SpkiFingerprint {
    static func testValue(_ byte: UInt8) -> SpkiFingerprint {
        guard let value = try? SpkiFingerprint(bytes: Data(repeating: byte, count: byteCount)) else {
            preconditionFailure("fingerprint")
        }
        return value
    }
}

private struct WriteFailure: Error {}

private actor FailingApplyStore: SmsStore {
    let base = InMemorySmsStore()
    var failApply = false

    func setFailApply(_ value: Bool) { failApply = value }

    func threads(peer: SpkiFingerprint) async throws -> [SmsThreadRecord] { try await base.threads(peer: peer) }
    func messages(peer: SpkiFingerprint, threadId: Int64) async throws -> [SmsMessageRecord] {
        try await base.messages(peer: peer, threadId: threadId)
    }
    func outbound(peer: SpkiFingerprint, threadId: Int64) async throws -> [SmsOutboundRecord] {
        try await base.outbound(peer: peer, threadId: threadId)
    }
    func cursors(peer: SpkiFingerprint) async throws -> SmsSyncCursors? { try await base.cursors(peer: peer) }
    func applyPage(
        peer: SpkiFingerprint,
        threads: [SmsThreadRecord],
        messages: [SmsMessageRecord],
        cursors: SmsSyncCursors
    ) async throws {
        if failApply { throw WriteFailure() }
        try await base.applyPage(peer: peer, threads: threads, messages: messages, cursors: cursors)
    }
    func insertOutbound(peer: SpkiFingerprint, _ record: SmsOutboundRecord) async throws {
        try await base.insertOutbound(peer: peer, record)
    }
    func updateOutbound(
        peer: SpkiFingerprint,
        clientMessageId: String,
        state: SmsOutboundState,
        providerMessageId: Int64
    ) async throws {
        try await base.updateOutbound(
            peer: peer,
            clientMessageId: clientMessageId,
            state: state,
            providerMessageId: providerMessageId
        )
    }
    func diagnostics(peer: SpkiFingerprint) async throws -> SmsStoreDiagnostics {
        try await base.diagnostics(peer: peer)
    }
    func purgeAll(peer: SpkiFingerprint) async throws { try await base.purgeAll(peer: peer) }
}

@Suite struct SmsSyncClientTests {
    private static let peer = SpkiFingerprint.testValue(7)

    private static func response(
        high: UInt64 = 0,
        backfill: UInt64 = 0,
        complete: Bool = false,
        messageIds: [UInt64] = []
    ) -> Tandem_V1_SmsSyncResponse {
        var response = Tandem_V1_SmsSyncResponse()
        response.status = .ok
        response.highWatermarkID = high
        response.backfillCursorID = backfill
        response.backfillComplete = complete
        response.messages = messageIds.map { id in
            var message = Tandem_V1_SmsMessage()
            message.id = id
            message.threadID = 1
            message.body = "b"
            return message
        }
        return response
    }

    private static func requests(_ session: FakeTandemSession) async -> [Tandem_V1_SmsSyncRequest] {
        await session.sent.compactMap {
            if case .smsSyncRequest(let request) = $0.payload { request } else { nil }
        }
    }

    @Test func smsSyncClient_requestSyncWithStoredCursors_sendsCursorsOnSmsChannel() async throws {
        let store = InMemorySmsStore()
        try await store.applyPage(
            peer: Self.peer, threads: [], messages: [],
            cursors: SmsSyncCursors(highWatermarkId: 4990, backfillCursorId: 3000, backfillComplete: false)
        )
        let session = FakeTandemSession()
        await SmsSyncClient(peer: Self.peer, store: store, session: session).requestSync()

        let sent = await session.sent
        #expect(sent.first?.channel == .sms)
        let request = try #require(await Self.requests(session).first)
        #expect(request.sinceID == 4990)
        #expect(request.backfillBeforeID == 3000)
    }

    @Test func smsSyncClient_requestSyncEmptyStore_sendsZeroCursors() async throws {
        let session = FakeTandemSession()
        await SmsSyncClient(peer: Self.peer, store: InMemorySmsStore(), session: session).requestSync()

        let request = try #require(await Self.requests(session).first)
        #expect(request.sinceID == 0)
        #expect(request.backfillBeforeID == 0)
    }

    @Test func smsSyncClient_pageWithBackfill_commitsRowsAndCursorsThenRequestsNextPage() async throws {
        let store = InMemorySmsStore()
        let session = FakeTandemSession()
        let client = SmsSyncClient(peer: Self.peer, store: store, session: session)

        await client.handle(Self.response(high: 5000, backfill: 4000, messageIds: [5000, 4000]))

        #expect(try await store.cursors(peer: Self.peer)
            == SmsSyncCursors(highWatermarkId: 5000, backfillCursorId: 4000, backfillComplete: false))
        #expect(try await store.diagnostics(peer: Self.peer).messageIds == [4000, 5000])
        let next = try #require(await Self.requests(session).first)
        #expect(next.sinceID == 5000)
        #expect(next.backfillBeforeID == 4000)
    }

    @Test func smsSyncClient_backfillComplete_setsStatusCompleteAndRequestsNothing() async throws {
        let session = FakeTandemSession()
        let client = SmsSyncClient(peer: Self.peer, store: InMemorySmsStore(), session: session)

        await client.handle(Self.response(high: 5000, backfill: 10, complete: true, messageIds: [10]))

        #expect(await client.syncStatus == .complete)
        #expect(await Self.requests(session).isEmpty)
    }

    @Test func smsSyncClient_unsolicitedPushUnsetBackfillFields_keepsStoredCursorsAndSendsNoRequest() async throws {
        let store = InMemorySmsStore()
        let session = FakeTandemSession()
        let client = SmsSyncClient(peer: Self.peer, store: store, session: session)
        await client.handle(Self.response(high: 5000, backfill: 10, complete: true, messageIds: [10]))

        await client.handle(Self.response(high: 5001, messageIds: [5001]))

        #expect(try await store.cursors(peer: Self.peer)
            == SmsSyncCursors(highWatermarkId: 5001, backfillCursorId: 10, backfillComplete: true))
        #expect(await Self.requests(session).isEmpty)
    }

    @Test func smsSyncClient_storeWriteFailureMidBatch_leavesCursorsUnchanged() async throws {
        let store = FailingApplyStore()
        let client = SmsSyncClient(peer: Self.peer, store: store, session: FakeTandemSession())
        await client.handle(Self.response(high: 100, backfill: 50, messageIds: [100, 50]))
        await store.setFailApply(true)

        await client.handle(Self.response(high: 200, backfill: 20, messageIds: [200, 20]))

        #expect(try await store.cursors(peer: Self.peer)
            == SmsSyncCursors(highWatermarkId: 100, backfillCursorId: 50, backfillComplete: false))
        #expect(try await store.diagnostics(peer: Self.peer).messageIds == [50, 100])
    }

    @Test func smsSyncClient_permissionRequiredResponse_setsStatusPermissionRequired() async throws {
        let client = SmsSyncClient(peer: Self.peer, store: InMemorySmsStore(), session: FakeTandemSession())
        var response = Tandem_V1_SmsSyncResponse()
        response.status = .permissionRequired

        await client.handle(response)

        #expect(await client.syncStatus == .permissionRequired)
    }

    @Test func smsSyncClient_sendStatusSent_updatesOptimisticRowByClientMessageId() async throws {
        let store = InMemorySmsStore()
        try await store.insertOutbound(
            peer: Self.peer,
            SmsOutboundRecord(clientMessageId: "c-1", threadId: 1, address: "a", body: "b", timestampMs: 1)
        )
        let client = SmsSyncClient(peer: Self.peer, store: store, session: FakeTandemSession())
        var status = Tandem_V1_SendSmsStatus()
        status.clientMessageID = "c-1"
        status.state = .sent
        status.providerMessageID = 77

        await client.handle(status)

        let row = try #require(await store.outbound(peer: Self.peer, threadId: 1).first)
        #expect(row.state == .sent)
        #expect(row.providerMessageId == 77)
    }

    @Test func smsSyncClient_syncedRowMatchingSentProviderId_leavesOneMessage() async throws {
        let store = InMemorySmsStore()
        try await store.insertOutbound(
            peer: Self.peer,
            SmsOutboundRecord(clientMessageId: "c-1", threadId: 1, address: "a", body: "b", timestampMs: 1)
        )
        let client = SmsSyncClient(peer: Self.peer, store: store, session: FakeTandemSession())
        var status = Tandem_V1_SendSmsStatus()
        status.clientMessageID = "c-1"
        status.state = .sent
        status.providerMessageID = 77
        await client.handle(status)

        await client.handle(Self.response(high: 77, backfill: 77, complete: true, messageIds: [77]))

        #expect(try await store.outbound(peer: Self.peer, threadId: 1).isEmpty)
        #expect(try await store.messages(peer: Self.peer, threadId: 1).map(\.id) == [77])
    }

    @Test func smsSyncClient_sentStatusAfterProviderRowSynced_leavesOneMessage() async throws {
        let store = InMemorySmsStore()
        try await store.insertOutbound(
            peer: Self.peer,
            SmsOutboundRecord(clientMessageId: "c-1", threadId: 1, address: "a", body: "b", timestampMs: 1)
        )
        let client = SmsSyncClient(peer: Self.peer, store: store, session: FakeTandemSession())
        await client.handle(Self.response(high: 77, backfill: 77, complete: true, messageIds: [77]))
        var status = Tandem_V1_SendSmsStatus()
        status.clientMessageID = "c-1"
        status.state = .sent
        status.providerMessageID = 77

        await client.handle(status)

        #expect(try await store.outbound(peer: Self.peer, threadId: 1).isEmpty)
        #expect(try await store.messages(peer: Self.peer, threadId: 1).map(\.id) == [77])
    }

    @Test func smsSyncClient_simList_replacesPrevious() async throws {
        let client = SmsSyncClient(peer: Self.peer, store: InMemorySmsStore(), session: FakeTandemSession())
        var first = Tandem_V1_SimList()
        first.subscriptions = [Tandem_V1_SimList.Subscription()]

        await client.handle(first)
        await client.handle(Tandem_V1_SimList())

        #expect(await client.simList?.subscriptions.isEmpty == true)
    }
}
