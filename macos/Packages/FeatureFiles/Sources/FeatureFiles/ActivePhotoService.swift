import Foundation
import TandemProtocol

/// Routes ``PhotoService`` calls to whichever session's photo service is currently attached
/// (``attach(_:)`` / ``detach()``), so one long-lived photo grid keeps working across reconnects.
/// Calls between sessions fail with ``PhotoServiceError/disconnected``.
public final class ActivePhotoService: PhotoService, @unchecked Sendable {
    private let lock = NSLock()
    private var current: (any PhotoService)?

    public init() {}

    public func attach(_ service: any PhotoService) {
        lock.withLock { current = service }
    }

    public func detach() {
        lock.withLock { current = nil }
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
