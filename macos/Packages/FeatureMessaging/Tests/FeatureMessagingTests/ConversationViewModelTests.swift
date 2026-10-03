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

private struct StubSyncSource: ConversationSyncSource {
    var sims: [SimOption] = []
    var errors: [String: Tandem_V1_SendSmsErrorCode] = [:]

    func simOptions() async -> [SimOption] { sims }
    func sendErrorCode(clientMessageId: String) async -> Tandem_V1_SendSmsErrorCode? { errors[clientMessageId] }
}

private final class IdSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0

    func make() -> String {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        return "cid-\(next)"
    }
}

@MainActor
@Suite struct ConversationViewModelTests {
    private static let peer = SpkiFingerprint.testValue(7)

    private struct Fixture {
        let store = InMemorySmsStore()
        let session = FakeTandemSession()
        let ids = IdSequence()
    }

    private static func makeViewModel(_ fixture: Fixture, source: StubSyncSource = StubSyncSource()) async throws
        -> ConversationViewModel {
        try await fixture.store.applyPage(
            peer: peer,
            threads: [SmsThreadRecord(
                threadId: 1, address: "+41791234567", snippet: "", lastMessageAtMs: 1, unreadCount: 0
            )],
            messages: [],
            cursors: SmsSyncCursors(highWatermarkId: 0, backfillCursorId: 0, backfillComplete: true)
        )
        let ids = fixture.ids
        return ConversationViewModel(
            peer: peer,
            threadId: 1,
            title: "Ada",
            smsStore: fixture.store,
            session: fixture.session,
            syncSource: source,
            now: { Date(timeIntervalSince1970: 100) },
            makeClientMessageId: { ids.make() }
        )
    }

    private static func requests(_ session: FakeTandemSession) async -> [Tandem_V1_SendSmsRequest] {
        await session.sent.compactMap {
            if case .sendSmsRequest(let request) = $0.payload { request } else { nil }
        }
    }

    private static func message(_ id: UInt64, atMs: UInt64, type: Tandem_V1_SmsMessageType = .inbox)
        -> Tandem_V1_SmsMessage {
        var message = Tandem_V1_SmsMessage()
        message.id = id
        message.threadID = 1
        message.body = "m\(id)"
        message.timestampMs = atMs
        message.type = type
        return message
    }

    @Test func composeViewModel_sendTapped_appendsBubbleInSendingState() async throws {
        let fixture = Fixture()
        let viewModel = try await Self.makeViewModel(fixture)
        viewModel.draft = "Hello"

        await viewModel.sendTapped()

        #expect(viewModel.bubbles.map(\.state) == [.sending])
        #expect(viewModel.bubbles.first?.body == "Hello")
        #expect(viewModel.draft.isEmpty)
        let request = try #require(await Self.requests(fixture.session).first)
        #expect(request.clientMessageID == "cid-1")
        #expect(request.address == "+41791234567")
        #expect(request.threadID == 1)
        #expect(request.subscriptionID == 0)
        #expect(request.body == "Hello")
    }

    @Test func composeViewModel_sentThenDeliveredStatus_bubbleStateDelivered() async throws {
        let fixture = Fixture()
        let viewModel = try await Self.makeViewModel(fixture)
        viewModel.draft = "Hello"
        await viewModel.sendTapped()

        try await fixture.store.updateOutbound(
            peer: Self.peer, clientMessageId: "cid-1", state: .sent, providerMessageId: 0
        )
        await viewModel.reload()
        #expect(viewModel.bubbles.map(\.state) == [.sent])

        try await fixture.store.updateOutbound(
            peer: Self.peer, clientMessageId: "cid-1", state: .delivered, providerMessageId: 0
        )
        await viewModel.reload()
        #expect(viewModel.bubbles.map(\.state) == [.delivered])
    }

    @Test func composeViewModel_failedNoServiceStatus_bubbleFailedWithRetry() async throws {
        let fixture = Fixture()
        let source = StubSyncSource(errors: ["cid-1": .noService])
        let viewModel = try await Self.makeViewModel(fixture, source: source)
        viewModel.draft = "Hello"
        await viewModel.sendTapped()

        try await fixture.store.updateOutbound(
            peer: Self.peer, clientMessageId: "cid-1", state: .failed, providerMessageId: 0
        )
        await viewModel.reload()

        #expect(viewModel.bubbles.map(\.state) == [.failed(.noService)])
        #expect(SendFailure.noService.reason == "no service")
    }

    @Test func composeViewModel_retryTapped_sendsSameBodyWithNewClientMessageId() async throws {
        let fixture = Fixture()
        let viewModel = try await Self.makeViewModel(fixture)
        viewModel.draft = "Hello"
        await viewModel.sendTapped()
        try await fixture.store.updateOutbound(
            peer: Self.peer, clientMessageId: "cid-1", state: .failed, providerMessageId: 0
        )
        await viewModel.reload()
        let failed = try #require(viewModel.bubbles.first)

        await viewModel.retryTapped(failed)

        let requests = await Self.requests(fixture.session)
        #expect(requests.map(\.clientMessageID) == ["cid-1", "cid-2"])
        #expect(requests.map(\.body) == ["Hello", "Hello"])
        #expect(viewModel.bubbles.map(\.id) == ["cid-2"])
        #expect(viewModel.bubbles.map(\.state) == [.sending])
    }

    @Test func composeViewModel_twoSimsInSimList_showsSimPickerBeforeSend() async throws {
        let fixture = Fixture()
        let sims = [SimOption(id: 11, name: "Work"), SimOption(id: 12, name: "Home")]
        let viewModel = try await Self.makeViewModel(fixture, source: StubSyncSource(sims: sims))
        await viewModel.reload()
        #expect(viewModel.showsSimPicker)
        #expect(viewModel.selectedSubscriptionId == 11)

        viewModel.selectedSubscriptionId = 12
        viewModel.draft = "Hello"
        await viewModel.sendTapped()

        #expect(await Self.requests(fixture.session).first?.subscriptionID == 12)
    }

    @Test func composeViewModel_oneSimInSimList_hidesPickerAndOmitsSubscriptionId() async throws {
        let fixture = Fixture()
        let viewModel = try await Self.makeViewModel(
            fixture, source: StubSyncSource(sims: [SimOption(id: 11, name: "Work")])
        )
        viewModel.draft = "Hello"
        await viewModel.sendTapped()

        #expect(!viewModel.showsSimPicker)
        #expect(await Self.requests(fixture.session).first?.subscriptionID == 0)
    }

    @Test func messageViewModel_threadMessages_orderedAscendingByTimestamp() async throws {
        let fixture = Fixture()
        let viewModel = try await Self.makeViewModel(fixture)
        try await fixture.store.applyPage(
            peer: Self.peer,
            threads: [],
            messages: [
                SmsSyncClientFixtures.record(Self.message(3, atMs: 300)),
                SmsSyncClientFixtures.record(Self.message(1, atMs: 100, type: .sent)),
                SmsSyncClientFixtures.record(Self.message(2, atMs: 200))
            ],
            cursors: SmsSyncCursors(highWatermarkId: 3, backfillCursorId: 0, backfillComplete: true)
        )

        await viewModel.reload()

        #expect(viewModel.bubbles.map(\.body) == ["m1", "m2", "m3"])
        #expect(viewModel.bubbles.map(\.isOutbound) == [true, false, false])
    }
}

private enum SmsSyncClientFixtures {
    static func record(_ message: Tandem_V1_SmsMessage) -> SmsMessageRecord {
        SmsMessageRecord(
            id: Int64(message.id),
            threadId: Int64(message.threadID),
            address: message.address,
            body: message.body,
            timestampMs: Int64(message.timestampMs),
            type: Int32(message.type.rawValue),
            subscriptionId: message.subscriptionID,
            deliveryStatus: 0
        )
    }
}
