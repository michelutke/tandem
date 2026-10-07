import Foundation
import Synchronization
import Testing
@testable import FeatureFiles

private final class MemoryBookmarkStore: BookmarkStoring {
    private let data = Mutex<Data?>(nil)

    func load() -> Data? { data.withLock { $0 } }
    func save(_ bookmark: Data?) { data.withLock { $0 = bookmark } }
}

private final class FakeBookmarking: FolderBookmarking, @unchecked Sendable {
    struct Failure: Error {}

    var resolveResult: Result<(url: URL, isStale: Bool), Failure> = .failure(Failure())
    var canMakeBookmark = true
    private let log = Mutex<[String]>([])

    var events: [String] { log.withLock { $0 } }

    func makeBookmark(for url: URL) throws -> Data {
        guard canMakeBookmark else { throw Failure() }
        return Data(url.path.utf8)
    }

    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        try resolveResult.get()
    }

    func startAccessing(_ url: URL) -> Bool {
        log.withLock { $0.append("start") }
        return true
    }

    func stopAccessing(_ url: URL) {
        log.withLock { $0.append("stop") }
    }
}

@Suite struct DownloadFolderStoreTests {
    private let defaultFolder = URL(fileURLWithPath: "/Users/test/Downloads/Tandem")
    private let chosen = URL(fileURLWithPath: "/Volumes/Data/Inbox")
    private let storage = MemoryBookmarkStore()
    private let bookmarking = FakeBookmarking()

    private func makeStore() -> DownloadFolderStore {
        DownloadFolderStore(defaultFolder: defaultFolder, storage: storage, bookmarking: bookmarking)
    }

    @Test func downloadFolderStore_nothingChosen_usesDefaultFolder() {
        let store = makeStore()

        #expect(store.current == defaultFolder)
        #expect(!store.isCustom)
    }

    @Test func downloadFolderStore_folderChosen_currentIsChosenFolderAndReadAtEachCall() throws {
        let store = makeStore()
        bookmarking.resolveResult = .success((chosen, false))

        try store.choose(chosen)

        #expect(store.current == chosen)
        #expect(store.isCustom)
    }

    @Test func downloadFolderStore_staleBookmark_refreshedAndStillUsed() throws {
        let store = makeStore()
        try store.choose(chosen)
        bookmarking.resolveResult = .success((chosen, true))

        #expect(store.current == chosen)
        #expect(storage.load() == Data(chosen.path.utf8))
    }

    @Test func downloadFolderStore_staleBookmarkCannotRefresh_fallsBackToDefault() throws {
        let store = makeStore()
        try store.choose(chosen)
        bookmarking.resolveResult = .success((chosen, true))
        bookmarking.canMakeBookmark = false

        #expect(store.current == defaultFolder)
    }

    @Test func downloadFolderStore_unresolvableBookmark_fallsBackToDefault() throws {
        let store = makeStore()
        try store.choose(chosen)

        #expect(store.current == defaultFolder)
    }

    @Test func downloadFolderStore_withAccessOnChosenFolder_opensAndClosesScope() throws {
        let store = makeStore()
        try store.choose(chosen)
        bookmarking.resolveResult = .success((chosen, false))

        let folder = store.withAccess { $0 }

        #expect(folder == chosen)
        #expect(bookmarking.events == ["start", "stop"])
    }

    @Test func downloadFolderStore_withAccessOnDefaultFolder_opensNoScope() {
        let folder = makeStore().withAccess { $0 }

        #expect(folder == defaultFolder)
        #expect(bookmarking.events.isEmpty)
    }

    @Test func downloadFolderStore_resetToDefault_clearsChoice() throws {
        let store = makeStore()
        try store.choose(chosen)
        bookmarking.resolveResult = .success((chosen, false))

        store.resetToDefault()

        #expect(store.current == defaultFolder)
    }
}
