import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import FeatureMessaging

private struct FixedSyncStatus: ThreadListSyncStatusSource {
    let status: ThreadListSyncStatus
    func current() async -> ThreadListSyncStatus { status }
}

@MainActor
struct ThreadListViewModelTests {
    // swiftlint:disable:next force_try
    private let peer = try! SpkiFingerprint(bytes: Data(repeating: 0xA1, count: SpkiFingerprint.byteCount))
    private let cursors = SmsSyncCursors(highWatermarkId: 0, backfillCursorId: 0, backfillComplete: true)

    private func thread(
        _ id: Int64,
        address: String = "+41791234567",
        snippet: String = "hi",
        at timestampMs: Int64 = 1,
        unread: Int32 = 0
    ) -> SmsThreadRecord {
        SmsThreadRecord(
            threadId: id,
            address: address,
            snippet: snippet,
            lastMessageAtMs: timestampMs,
            unreadCount: unread
        )
    }

    private func makeModel(
        threads: [SmsThreadRecord] = [],
        contacts: [ContactRecord] = [],
        status: ThreadListSyncStatus = .complete
    ) async throws -> ThreadListViewModel {
        let sms = InMemorySmsStore()
        try await sms.applyPage(peer: peer, threads: threads, messages: [], cursors: cursors)
        let contactsStore = InMemoryContactsStore()
        try await contactsStore.apply(peer: peer, contacts: contacts, deletedContactIds: [], watermarkMs: nil)
        let model = ThreadListViewModel(
            peer: peer,
            smsStore: sms,
            contactsStore: contactsStore,
            syncStatus: FixedSyncStatus(status: status),
            defaultRegion: "CH"
        )
        await model.reload()
        return model
    }

    @Test
    func threadListViewModel_threeThreads_sortedByLastMessageDescending() async throws {
        let model = try await makeModel(threads: [thread(1, at: 1), thread(3, at: 3), thread(2, at: 2)])
        #expect(model.rows.map(\.id) == [3, 2, 1])
        #expect(model.state == .loaded)
    }

    @Test
    func threadListViewModel_unresolvedE164Address_displaysInternationalFormat() async throws {
        let model = try await makeModel(threads: [thread(1, address: "+41791234567")])
        #expect(model.rows.first?.title == "+41 79 123 45 67")
    }

    @Test
    func threadListViewModel_resolvedContactWithThumbnail_exposesAvatar() async throws {
        let thumbnail = Data([1, 2, 3])
        let contact = ContactRecord(
            contactId: "c1",
            displayName: "Ada",
            phoneNumbers: [ContactPhoneRecord(number: "+41791234567", normalizedE164: "+41791234567")],
            photoThumbnail: thumbnail,
            updatedAtMs: 1
        )
        let model = try await makeModel(threads: [thread(1)], contacts: [contact])
        #expect(model.rows.first?.title == "Ada")
        #expect(model.rows.first?.avatarThumbnail == thumbnail)
    }

    @Test
    func threadListViewModel_unreadCountThree_badgeShowsThree() async throws {
        let model = try await makeModel(threads: [thread(1, unread: 3), thread(2, unread: 0)])
        let badges = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.id, $0.unreadBadge) })
        #expect(badges[1] == "3")
        #expect(badges[2] == .some(nil))
    }

    @Test
    func threadListViewModel_emptyStoreSyncInProgress_stateIsLoading() async throws {
        let model = try await makeModel(status: .syncing)
        #expect(model.state == .loading)
    }

    @Test
    func threadListViewModel_emptyStoreSyncComplete_stateIsEmpty() async throws {
        let model = try await makeModel(status: .complete)
        #expect(model.state == .empty)
    }

    @Test
    func threadListViewModel_permissionRequiredStatus_stateIsPermissionRequired() async throws {
        let model = try await makeModel(status: .permissionRequired)
        #expect(model.state == .permissionRequired)
    }

    @Test
    func threadListViewModel_senderIdWithBidiOverride_displayedSanitized() async throws {
        let model = try await makeModel(threads: [thread(1, address: "BA\u{202E}NK\u{0007}", snippet: "a\u{202E}b")])
        #expect(model.rows.first?.title == "BANK")
        #expect(model.rows.first?.snippet == "ab")
    }
}
