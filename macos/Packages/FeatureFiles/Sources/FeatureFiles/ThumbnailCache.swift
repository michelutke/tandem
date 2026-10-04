import CryptoKit
import Foundation
import TandemCrypto
import TandemStore

/// On-disk LRU cache of `ThumbResult` PNGs (backlog E41-06, PRD F-7.4), keyed by
/// (peer, photo id, maxPx) with a byte cap. Entries live under one subdirectory per peer so
/// ``purgeAll(peer:)`` (``PeerDataPurging``, E14-13) deletes a phone's thumbnails on unpair.
/// Recency is each file's modification date, set from the injected `now` on every store and hit,
/// so eviction order survives re-opening the same directory. The composition root points
/// `directory` at the app container's Caches directory; tests use a temporary one.
public actor ThumbnailCache: PeerDataPurging {
    public static let defaultCapBytes = 256 * 1024 * 1024

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let pngTrailer = Data([
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ])
    private static var ownerOnlyFile: [FileAttributeKey: Any] { [.posixPermissions: 0o600] }
    private static var ownerOnlyDirectory: [FileAttributeKey: Any] { [.posixPermissions: 0o700] }

    private struct CachedFile {
        let url: URL
        let size: Int
        let modified: Date
    }

    private let directory: URL
    private let capBytes: Int
    private let now: @Sendable () -> Date
    private let fileManager = FileManager.default
    private var index: [String: CachedFile]?

    public init(
        directory: URL,
        capBytes: Int = ThumbnailCache.defaultCapBytes,
        now: @escaping @Sendable () -> Date
    ) throws {
        self.directory = directory
        self.capBytes = capBytes
        self.now = now
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: Self.ownerOnlyDirectory
        )
    }

    /// The cached PNG for the key, marking it most recently used; `nil` on a miss. A file that is
    /// not a complete PNG (truncated or corrupt) is deleted and reported as a miss.
    public func data(peer: SpkiFingerprint, id: String, maxPx: UInt32) -> Data? {
        let url = fileURL(peer: peer, id: id, maxPx: maxPx)
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        guard Self.isCompletePNG(bytes) else {
            try? fileManager.removeItem(at: url)
            index?[Self.indexKey(url)] = nil
            return nil
        }
        let modified = now()
        try? fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let key = Self.indexKey(url)
        if index?[key] != nil { index?[key] = CachedFile(url: url, size: bytes.count, modified: modified) }
        return bytes
    }

    /// Stores `bytes` atomically (owner-only, 0600) and evicts least recently used entries until
    /// the total is within the cap. Bytes that are not a complete PNG, or larger than the cap, are
    /// not stored. Best effort: a write failure just leaves the thumbnail uncached.
    public func store(_ bytes: Data, peer: SpkiFingerprint, id: String, maxPx: UInt32) {
        guard Self.isCompletePNG(bytes), bytes.count <= capBytes else { return }
        let url = fileURL(peer: peer, id: id, maxPx: maxPx)
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: Self.ownerOnlyDirectory
            )
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
            var attributes = Self.ownerOnlyFile
            let modified = now()
            attributes[.modificationDate] = modified
            guard fileManager.createFile(atPath: temporary.path, contents: bytes, attributes: attributes) else {
                return
            }
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            loadIndexIfNeeded()
            index?[Self.indexKey(url)] = CachedFile(url: url, size: bytes.count, modified: modified)
        } catch {
            return
        }
        evictToCap(keeping: url)
    }

    /// ``PeerDataPurging`` conformance: deletes every cached thumbnail of `peer`.
    public func purgeAll(peer: SpkiFingerprint) async throws {
        let peerDirectory = directory.appendingPathComponent(peer.hexString, isDirectory: true)
        guard fileManager.fileExists(atPath: peerDirectory.path) else { return }
        let purgedPrefix = Self.indexKey(peerDirectory) + "/"
        try fileManager.removeItem(at: peerDirectory)
        index = index?.filter { !$0.key.hasPrefix(purgedPrefix) }
    }

    private func fileURL(peer: SpkiFingerprint, id: String, maxPx: UInt32) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory
            .appendingPathComponent(peer.hexString, isDirectory: true)
            .appendingPathComponent("\(digest)_\(maxPx).png")
    }

    private func loadIndexIfNeeded() {
        guard index == nil else { return }
        index = Dictionary(cachedFiles().map { (Self.indexKey($0.url), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func evictToCap(keeping keptURL: URL) {
        loadIndexIfNeeded()
        let keptKey = Self.indexKey(keptURL)
        var total = index?.values.reduce(0) { $0 + $1.size } ?? 0
        while total > capBytes {
            guard let oldest = index?.lazy.filter({ $0.key != keptKey })
                .min(by: { Self.isOlder($0.value, than: $1.value) }) else { return }
            try? fileManager.removeItem(at: oldest.value.url)
            guard !fileManager.fileExists(atPath: oldest.value.url.path) else { return }
            index?[oldest.key] = nil
            total -= oldest.value.size
        }
    }

    private static func isOlder(_ lhs: CachedFile, than rhs: CachedFile) -> Bool {
        (lhs.modified, lhs.url.path) < (rhs.modified, rhs.url.path)
    }

    private func cachedFiles() -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        var files: [CachedFile] = []
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            files.append(CachedFile(
                url: url,
                size: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast
            ))
        }
        return files
    }

    private static func indexKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private static func isCompletePNG(_ bytes: Data) -> Bool {
        bytes.count >= pngSignature.count + pngTrailer.count
            && bytes.starts(with: pngSignature)
            && bytes.suffix(pngTrailer.count) == pngTrailer
    }
}
