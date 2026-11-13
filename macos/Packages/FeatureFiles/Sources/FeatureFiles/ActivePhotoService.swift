import Foundation
import TandemProtocol

/// Routes ``PhotoService`` calls to whichever session's photo service is currently attached
/// (``attach(_:)`` / ``detach()``), so one long-lived photo grid keeps working across reconnects.
/// Calls between sessions fail with ``PhotoServiceError/disconnected``.
public final class ActivePhotoService: PhotoService, OriginalOfferExpecting, @unchecked Sendable {
    private let lock = NSLock()
    private var current: (any PhotoService)?
    private var offers: (any OriginalOfferExpecting)?

    public init() {}

    public func attach(_ service: any PhotoService, offers: (any OriginalOfferExpecting)? = nil) {
        lock.withLock {
            current = service
            self.offers = offers
        }
    }

    public func detach() {
        lock.withLock {
            current = nil
            offers = nil
        }
    }

    public func expectOriginal(transferId: String) async {
        let offers = lock.withLock { self.offers }
        await offers?.expectOriginal(transferId: transferId)
    }

    public func forgetOriginal(transferId: String) async {
        let offers = lock.withLock { self.offers }
        await offers?.forgetOriginal(transferId: transferId)
    }

    public func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        try await attached().fetchPage(cursor: cursor, limit: limit)
    }

    public func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data {
        try await attached().fetchThumbnail(id: id, maxPx: maxPx)
    }

    public func requestMorePhotos() async throws {
        try await attached().requestMorePhotos()
    }

    public func requestOriginal(id: String, transferId: String) async throws {
        try await attached().requestOriginal(id: id, transferId: transferId)
    }

    private func attached() throws -> any PhotoService {
        guard let service = lock.withLock({ current }) else { throw PhotoServiceError.disconnected }
        return service
    }
}
