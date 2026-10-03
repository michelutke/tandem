import Foundation
import TandemCrypto
import TandemProtocol

/// Decorates a ``PhotoService`` with the on-disk ``ThumbnailCache`` for one peer (backlog
/// E41-06): a cached thumbnail is served without any service call; misses are fetched and stored.
public struct CachingPhotoService: PhotoService {
    private let base: any PhotoService
    private let cache: ThumbnailCache
    private let peer: SpkiFingerprint

    public init(base: any PhotoService, cache: ThumbnailCache, peer: SpkiFingerprint) {
        self.base = base
        self.cache = cache
        self.peer = peer
    }

    public func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        try await base.fetchPage(cursor: cursor, limit: limit)
    }

    public func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data {
        if let cached = await cache.data(peer: peer, id: id, maxPx: maxPx) { return cached }
        let bytes = try await base.fetchThumbnail(id: id, maxPx: maxPx)
        await cache.store(bytes, peer: peer, id: id, maxPx: maxPx)
        return bytes
    }

    public func requestMorePhotos() async throws {
        try await base.requestMorePhotos()
    }

    public func requestOriginal(id: String, transferId: String) async throws {
        try await base.requestOriginal(id: id, transferId: transferId)
    }
}
