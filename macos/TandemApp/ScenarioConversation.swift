#if DEBUG
import FeatureMessaging
import Foundation
import SwiftUI
import TandemCrypto
import TandemProtocol
import TandemStore

extension ScenarioView {
    /// One seeded conversation (E50-08): an inbound and an outbound message, composer visible, so
    /// the message view renders without a phone.
    @MainActor
    static func makeConversationSeededView() -> some View {
        ConversationView(viewModel: makeSeededConversationViewModel())
    }

    @MainActor
    private static func makeSeededConversationViewModel() -> ConversationViewModel {
        // swiftlint:disable:next force_try
        let peer = try! SpkiFingerprint(bytes: Data(repeating: 0xA2, count: SpkiFingerprint.byteCount))
        let smsStore = InMemorySmsStore()
        let address = "+41791234567"
        let thread = SmsThreadRecord(
            threadId: 1, address: address, snippet: "On my way", lastMessageAtMs: 2, unreadCount: 0
        )
        let messages = [
            SmsMessageRecord(
                id: 1, threadId: 1, address: address, body: "See you at 6", timestampMs: 1,
                type: Int32(Tandem_V1_SmsMessageType.inbox.rawValue), subscriptionId: 0, deliveryStatus: 0
            ),
            SmsMessageRecord(
                id: 2, threadId: 1, address: address, body: "On my way", timestampMs: 2,
                type: Int32(Tandem_V1_SmsMessageType.sent.rawValue), subscriptionId: 0, deliveryStatus: 0
            )
        ]
        let cursors = SmsSyncCursors(highWatermarkId: 2, backfillCursorId: 0, backfillComplete: true)
        Task { try? await smsStore.applyPage(peer: peer, threads: [thread], messages: messages, cursors: cursors) }
        return ConversationViewModel(
            peer: peer,
            threadId: 1,
            title: "Ada Lovelace",
            smsStore: smsStore,
            session: FakeTandemSession(),
            syncSource: SeededConversationSyncSource(),
            now: { Date() }
        )
    }
}

private struct SeededConversationSyncSource: ConversationSyncSource {
    func simOptions() async -> [SimOption] { [] }
    func sendErrorCode(clientMessageId: String) async -> Tandem_V1_SendSmsErrorCode? { nil }
}
#endif
