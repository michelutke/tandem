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
    public let lastMessageAtMs: Int64

    public var isUnread: Bool { unreadBadge != nil }

    /// "14:21" for today, "Yesterday", otherwise "7 Oct" (ui-spec §7.1 thread rows).
    public func timeText(calendar: Calendar = .current) -> String {
        guard lastMessageAtMs > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(lastMessageAtMs) / 1000)
        if calendar.isDateInToday(date) { return Self.format(date, "HH:mm", calendar) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.format(date, "d MMM", calendar)
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Drives the Messages thread list (backlog E50-07, PRD F-8.1, UC-18): threads from ``SmsStore``
/// newest first, titled by cached contact name, else international number format, else the
/// alphanumeric sender id as-is. Never logs names, numbers or snippets (invariant 7).
@MainActor
@Observable
public final class ThreadListViewModel {
    public private(set) var rows: [ThreadRow] = []
    public private(set) var state: ThreadListState = .loading
    public var searchQuery = ""

    /// ``rows`` narrowed by ``searchQuery`` (case-insensitive over title and snippet).
    public var visibleRows: [ThreadRow] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.snippet.localizedCaseInsensitiveContains(query)
        }
    }

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
            snippet: Self.sanitize(Self.joiningLines(thread.snippet)),
            unreadBadge: thread.unreadCount > 0 ? String(thread.unreadCount) : nil,
            avatarThumbnail: thumbnail,
            lastMessageAtMs: thread.lastMessageAtMs
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

    private static func joiningLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func sanitize(_ text: String) -> String {
        DisplayStringSanitizer.sanitize(Data(text.utf8), kind: .title)
    }
}
