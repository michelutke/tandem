import Foundation
import Testing
import TandemCrypto
@testable import TandemStore

private enum StoreKind: String, CaseIterable, Sendable {
    case inMemory
    case grdb
}

private func makeStore(_ kind: StoreKind) throws -> any SmsStore {
    switch kind {
    case .inMemory:
        return InMemorySmsStore()
    case .grdb:
        let directory = try SmsFixtures.makeTempDirectory()
        return try GrdbSmsStore.open(at: directory.appendingPathComponent("sms.sqlite"))
    }
}

struct SmsStoreContractTests {
    private let peerA = SmsFixtures.peerA
    private let peerB = SmsFixtures.peerB

    @Test(arguments: StoreKind.allCases)
    private func applyPage_sameMessageIdTwice_leavesOneRow(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        let page = [SmsFixtures.message(5)]
        try await store.applyPage(
            peer: peerA, threads: [SmsFixtures.thread(1)], messages: page, cursors: SmsFixtures.cursors
        )
        try await store.applyPage(
            peer: peerA, threads: [SmsFixtures.thread(1)], messages: page, cursors: SmsFixtures.cursors
        )

        #expect(try await store.messages(peer: peerA, threadId: 1).count == 1)
        #expect(try await store.threads(peer: peerA).count == 1)
    }

    @Test(arguments: StoreKind.allCases)
    private func messages_threadMessages_orderedAscendingByTimestamp(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        let messages = [
            SmsFixtures.message(3, timestampMs: 300),
            SmsFixtures.message(1, timestampMs: 100),
            SmsFixtures.message(2, timestampMs: 200),
            SmsFixtures.message(9, thread: 2, timestampMs: 50)
        ]
        try await store.applyPage(peer: peerA, threads: [], messages: messages, cursors: SmsFixtures.cursors)

        #expect(try await store.messages(peer: peerA, threadId: 1).map(\.id) == [1, 2, 3])
    }

    @Test(arguments: StoreKind.allCases)
    private func threads_mostRecentFirst(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        let threads = [SmsFixtures.thread(1, lastMessageAtMs: 10), SmsFixtures.thread(2, lastMessageAtMs: 30)]
        try await store.applyPage(peer: peerA, threads: threads, messages: [], cursors: SmsFixtures.cursors)

        #expect(try await store.threads(peer: peerA).map(\.threadId) == [2, 1])
    }

    @Test(arguments: StoreKind.allCases)
    private func applyPage_persistsCursorsAndOverwritesPrevious(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        #expect(try await store.cursors(peer: peerA) == nil)

        let next = SmsSyncCursors(highWatermarkId: 20, backfillCursorId: 1, backfillComplete: true)
        try await store.applyPage(peer: peerA, threads: [], messages: [], cursors: SmsFixtures.cursors)
        try await store.applyPage(peer: peerA, threads: [], messages: [], cursors: next)

        #expect(try await store.cursors(peer: peerA) == next)
    }

    @Test(arguments: StoreKind.allCases)
    private func updateOutbound_stateAndProviderId_applied(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        let record = SmsOutboundRecord(clientMessageId: "c1", threadId: 1, address: "+41", body: "hi", timestampMs: 5)
        try await store.insertOutbound(peer: peerA, record)
        try await store.updateOutbound(peer: peerA, clientMessageId: "c1", state: .sent, providerMessageId: 77)
        try await store.updateOutbound(peer: peerA, clientMessageId: "missing", state: .failed, providerMessageId: 0)

        let rows = try await store.outbound(peer: peerA, threadId: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.state == .sent)
        #expect(rows.first?.providerMessageId == 77)
    }

    @Test(arguments: StoreKind.allCases)
    private func applyPage_messageMatchingProviderId_replacesOptimisticRow(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        let record = SmsOutboundRecord(clientMessageId: "c1", threadId: 1, address: "+41", body: "hi", timestampMs: 5)
        try await store.insertOutbound(peer: peerA, record)
        try await store.updateOutbound(peer: peerA, clientMessageId: "c1", state: .sent, providerMessageId: 42)
        try await store.applyPage(
            peer: peerA, threads: [], messages: [SmsFixtures.message(42)], cursors: SmsFixtures.cursors
        )

        #expect(try await store.outbound(peer: peerA, threadId: 1).isEmpty)
    }

    @Test(arguments: StoreKind.allCases)
    private func purgeAll_peerA_removesAllOfAAndKeepsB(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        for peer in [peerA, peerB] {
            try await store.applyPage(
                peer: peer,
                threads: [SmsFixtures.thread(1)],
                messages: [SmsFixtures.message(5)],
                cursors: SmsFixtures.cursors
            )
            try await store.insertOutbound(
                peer: peer,
                SmsOutboundRecord(clientMessageId: "c1", threadId: 1, address: "+41", body: "hi", timestampMs: 5)
            )
        }

        try await store.purgeAll(peer: peerA)

        let empty = SmsStoreDiagnostics(threadIds: [], messageIds: [], outboundCount: 0)
        #expect(try await store.diagnostics(peer: peerA) == empty)
        #expect(try await store.cursors(peer: peerA) == nil)
        #expect(try await store.threads(peer: peerB).count == 1)
        #expect(try await store.messages(peer: peerB, threadId: 1).count == 1)
        #expect(try await store.outbound(peer: peerB, threadId: 1).count == 1)
        #expect(try await store.cursors(peer: peerB) == SmsFixtures.cursors)
    }

    @Test(arguments: StoreKind.allCases)
    private func diagnostics_reportsCountsAndIdsOnly(kind: StoreKind) async throws {
        let store = try makeStore(kind)
        try await store.applyPage(
            peer: peerA,
            threads: [SmsFixtures.thread(1), SmsFixtures.thread(2)],
            messages: [SmsFixtures.message(7), SmsFixtures.message(5)],
            cursors: SmsFixtures.cursors
        )

        let diagnostics = try await store.diagnostics(peer: peerA)

        #expect(diagnostics.threadCount == 2)
        #expect(diagnostics.messageIds == [5, 7])
        let rendered = String(describing: diagnostics)
        #expect(!rendered.contains("secret"))
        #expect(!rendered.contains("+4179"))
    }
}
