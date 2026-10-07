#if DEBUG
import FeatureMessaging
import Foundation
import SwiftUI
import TandemCrypto
import TandemStore

extension ScenarioView {
    /// Three seeded threads (E50-07): a resolved contact, an unresolved international number with
    /// an unread badge, and an alphanumeric sender id, so the list renders without a phone.
    @MainActor
    static func makeThreadListSeededView() -> some View {
        ScenarioThreadListHost()
    }

    @MainActor
    fileprivate static func seededThreadListViewModel() -> ThreadListViewModel {
        makeSeededThreadListViewModel()
    }

    @MainActor
    private static func makeSeededThreadListViewModel() -> ThreadListViewModel {
        // swiftlint:disable:next force_try
        let peer = try! SpkiFingerprint(bytes: Data(repeating: 0xA1, count: SpkiFingerprint.byteCount))
        let smsStore = InMemorySmsStore()
        let contactsStore = InMemoryContactsStore()
        let threads = [
            SmsThreadRecord(
                threadId: 1, address: "+41791234567", snippet: "See you at 6", lastMessageAtMs: 3, unreadCount: 3
            ),
            SmsThreadRecord(
                threadId: 2, address: "+41442345678", snippet: "On my way", lastMessageAtMs: 2, unreadCount: 0
            ),
            SmsThreadRecord(
                threadId: 3, address: "BANK", snippet: "Your code is ready", lastMessageAtMs: 1, unreadCount: 0
            )
        ]
        let contact = ContactRecord(
            contactId: "seeded-contact",
            displayName: "Ada Lovelace",
            phoneNumbers: [ContactPhoneRecord(number: "+41442345678", normalizedE164: "+41442345678")],
            updatedAtMs: 1
        )
        let cursors = SmsSyncCursors(highWatermarkId: 0, backfillCursorId: 0, backfillComplete: true)
        let seedStores: @Sendable () async -> Void = {
            try? await smsStore.applyPage(peer: peer, threads: threads, messages: [], cursors: cursors)
            try? await contactsStore.apply(peer: peer, contacts: [contact], deletedContactIds: [], watermarkMs: nil)
        }
        return ThreadListViewModel(
            peer: peer,
            smsStore: smsStore,
            contactsStore: contactsStore,
            syncStatus: SeededCompleteSyncStatus(seedStores: seedStores),
            defaultRegion: "CH"
        )
    }
}

/// Holds the list's view model in `@State`: the scenario root re-evaluates its body, and a view
/// model built inline would restart loading every time.
private struct ScenarioThreadListHost: View {
    @State private var viewModel = ScenarioView.seededThreadListViewModel()

    var body: some View {
        ThreadListView(viewModel: viewModel)
    }
}

private struct SeededCompleteSyncStatus: ThreadListSyncStatusSource {
    let seedStores: @Sendable () async -> Void

    func current() async -> ThreadListSyncStatus {
        await seedStores()
        return .complete
    }
}
#endif
