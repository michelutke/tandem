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
        ScenarioConversationHost()
    }

    @MainActor
    fileprivate static func seededConversation() -> SeededConversation {
        let session = FakeTandemSession()
        let syncSource = SeededConversationSyncSource()
        let seeded = makeSeededConversationViewModel(session: session, syncSource: syncSource)
        return SeededConversation(
            session: session,
            syncSource: syncSource,
            viewModel: seeded.viewModel,
            seed: seeded.seed
        )
    }

    @MainActor
    private static func makeSeededConversationViewModel(
        session: FakeTandemSession,
        syncSource: SeededConversationSyncSource
    ) -> (viewModel: ConversationViewModel, seed: @Sendable () async -> Void) {
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
        let seed: @Sendable () async -> Void = {
            try? await smsStore.applyPage(peer: peer, threads: [thread], messages: messages, cursors: cursors)
        }
        let viewModel = ConversationViewModel(
            peer: peer,
            threadId: 1,
            title: "Ada Lovelace",
            smsStore: smsStore,
            session: session,
            syncSource: syncSource,
            now: { Date() }
        )
        return (viewModel, seed)
    }
}

private struct SeededConversation {
    let session: FakeTandemSession
    let syncSource: any ConversationSyncSource
    let viewModel: ConversationViewModel
    let seed: @Sendable () async -> Void
}

/// Holds the seeded conversation in `@State`: the scenario root re-evaluates its body, and a view
/// model built inline would restart loading every time.
private struct ScenarioConversationHost: View {
    @State private var conversation = ScenarioView.seededConversation()

    var body: some View {
        SeededConversationHost(seed: conversation.seed) {
            ConversationView(
                viewModel: conversation.viewModel,
                headerAccessory: ConversationCallHost.headerAccessory(
                    session: conversation.session,
                    syncSource: conversation.syncSource
                )
            )
        }
    }
}

/// Applies the seeded page before the conversation first loads, so the scenario never races its store.
private struct SeededConversationHost<Content: View>: View {
    let seed: @Sendable () async -> Void
    @ViewBuilder let content: () -> Content
    @State private var isSeeded = false

    var body: some View {
        if isSeeded {
            content()
        } else {
            Color.clear.task {
                await seed()
                isSeeded = true
            }
        }
    }
}

private struct SeededConversationSyncSource: ConversationSyncSource {
    func simOptions() async -> [SimOption] { [] }
    func sendErrorCode(clientMessageId: String) async -> Tandem_V1_SendSmsErrorCode? { nil }
}
#endif
