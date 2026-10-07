import Foundation

/// Where received files are written, read at each use so a change applies without a restart.
public protocol DestinationResolving: Sendable {
    var current: URL { get }
    /// Runs `body` with the destination's security scope open (a no-op for the default folder).
    func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T
}

/// A fixed destination, for callers and tests that never change folder.
public struct StaticDestination: DestinationResolving {
    public let current: URL

    public init(_ url: URL) {
        current = url
    }

    public func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        try body(current)
    }
}

/// Seam over security-scoped bookmark creation, resolution and scope access.
public protocol FolderBookmarking: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct SecurityScopedBookmarking: FolderBookmarking {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

public protocol BookmarkStoring: Sendable {
    func load() -> Data?
    func save(_ bookmark: Data?)
}

public struct UserDefaultsBookmarkStore: BookmarkStoring, @unchecked Sendable {
    private static let key = "downloadFolderBookmark"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Data? {
        defaults.data(forKey: Self.key)
    }

    public func save(_ bookmark: Data?) {
        defaults.set(bookmark, forKey: Self.key)
    }
}

/// The user-chosen download folder, persisted as a security-scoped bookmark. Falls back to
/// `defaultFolder` when nothing is chosen or the bookmark cannot be resolved or refreshed.
public final class DownloadFolderStore: DestinationResolving, @unchecked Sendable {
    public static let standard = DownloadFolderStore(
        defaultFolder: URL.downloadsDirectory.appendingPathComponent("Tandem", isDirectory: true),
        storage: UserDefaultsBookmarkStore(),
        bookmarking: SecurityScopedBookmarking()
    )

    public let defaultFolder: URL
    private let storage: any BookmarkStoring
    private let bookmarking: any FolderBookmarking

    public init(defaultFolder: URL, storage: any BookmarkStoring, bookmarking: any FolderBookmarking) {
        self.defaultFolder = defaultFolder
        self.storage = storage
        self.bookmarking = bookmarking
    }

    public var current: URL {
        chosenFolder() ?? defaultFolder
    }

    public var isCustom: Bool {
        chosenFolder() != nil
    }

    /// Persists `url` as the download folder; call with the URL an open panel returned.
    public func choose(_ url: URL) throws {
        storage.save(try bookmarking.makeBookmark(for: url))
    }

    public func resetToDefault() {
        storage.save(nil)
    }

    public func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let folder = chosenFolder()
        let started = folder.map(bookmarking.startAccessing) ?? false
        defer {
            if started, let folder { bookmarking.stopAccessing(folder) }
        }
        return try body(folder ?? defaultFolder)
    }

    private func chosenFolder() -> URL? {
        guard let bookmark = storage.load(), let resolved = try? bookmarking.resolve(bookmark) else { return nil }
        guard resolved.isStale else { return resolved.url }
        guard let refreshed = try? bookmarking.makeBookmark(for: resolved.url) else { return nil }
        storage.save(refreshed)
        return resolved.url
    }
}
