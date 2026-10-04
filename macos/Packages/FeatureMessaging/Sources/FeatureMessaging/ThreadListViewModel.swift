import Foundation
import Observation
import PhoneNumberKit
import TandemCrypto
import TandemProtocol
import TandemStore

public enum ThreadListSyncStatus: Sendable, Equatable {
    case syncing
    case complete
    case permissionRequired
}

/// Where the thread list learns the phone's SMS sync progress (the persisted cursors alone cannot
/// express PERMISSION_REQUIRED).
public protocol ThreadListSyncStatusSource: Sendable {
    func current() async -> ThreadListSyncStatus
}

public enum ThreadListState: Sendable, Equatable {
    case loading
    case empty
    case permissionRequired
    case loaded
}

/// One rendered conversation row. Every string is sanitized peer input and never logged
/// (invariant 7).
public struct ThreadRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let title: String
    public let snippet: String
    public let unreadBadge: String?
    public let avatarThumbnail: Data?
}

/// Drives the Messages thread list (backlog E50-07, PRD F-8.1, UC-18): threads from ``SmsStore``
/// newest first, titled by cached contact name, else international number format, else the
/// alphanumeric sender id as-is. Never logs names, numbers or snippets (invariant 7).
@MainActor
@Observable
public final class ThreadListViewModel {
    public private(set) var rows: [ThreadRow] = []
    public private(set) var state: ThreadListState = .loading

    public var unreadCount: Int { unreadTotal }

    @ObservationIgnored private var unreadTotal = 0
    @ObservationIgnored private let peer: SpkiFingerprint
    @ObservationIgnored private let smsStore: any SmsStore
    @ObservationIgnored private let contactsStore: any ContactsStore
    @ObservationIgnored private let syncStatus: any ThreadListSyncStatusSource
    @ObservationIgnored private let phoneNumberUtility = PhoneNumberUtility()
    @ObservationIgnored private let defaultRegion: String

    public init(
        peer: SpkiFingerprint,
        smsStore: any SmsStore,
        contactsStore: any ContactsStore,
        syncStatus: any ThreadListSyncStatusSource,
        defaultRegion: String = Locale.current.region?.identifier ?? "US"
    ) {
        self.peer = peer
        self.smsStore = smsStore
        self.contactsStore = contactsStore
        self.syncStatus = syncStatus
        self.defaultRegion = defaultRegion
    }

    public func reload() async {
        let status = await syncStatus.current()
        let threads = ((try? await smsStore.threads(peer: peer)) ?? [])
            .sorted { ($0.lastMessageAtMs, $0.threadId) > ($1.lastMessageAtMs, $1.threadId) }
        var built: [ThreadRow] = []
        for thread in threads {
            built.append(await row(for: thread))
        }
        rows = built
        unreadTotal = threads.reduce(0) { $0 + Int(max($1.unreadCount, 0)) }
        state = Self.state(status: status, hasThreads: !threads.isEmpty)
    }

    private static func state(status: ThreadListSyncStatus, hasThreads: Bool) -> ThreadListState {
        if status == .permissionRequired { return .permissionRequired }
        if hasThreads { return .loaded }
        return status == .syncing ? .loading : .empty
    }

    private func row(for thread: SmsThreadRecord) async -> ThreadRow {
        let contact = Self.isAlphanumericSenderId(thread.address)
            ? nil
            : try? await contactsStore.lookup(peer: peer, number: thread.address)
        let title = contact.map { Self.sanitize($0.displayName) } ?? unresolvedTitle(thread.address)
        let thumbnail = contact.flatMap { $0.photoThumbnail.isEmpty ? nil : $0.photoThumbnail }
        return ThreadRow(
            id: thread.threadId,
            title: title,
            snippet: Self.sanitize(thread.snippet),
            unreadBadge: thread.unreadCount > 0 ? String(thread.unreadCount) : nil,
            avatarThumbnail: thumbnail
        )
    }

    private func unresolvedTitle(_ address: String) -> String {
        guard !Self.isAlphanumericSenderId(address),
              let parsed = try? phoneNumberUtility.parse(address, withRegion: defaultRegion)
        else { return Self.sanitize(address) }
        return phoneNumberUtility.format(parsed, toType: .international)
    }

    private static func isAlphanumericSenderId(_ address: String) -> Bool {
        address.contains { $0.isLetter }
    }

    private static func sanitize(_ text: String) -> String {
        DisplayStringSanitizer.sanitize(Data(text.utf8), kind: .title)
    }
}
