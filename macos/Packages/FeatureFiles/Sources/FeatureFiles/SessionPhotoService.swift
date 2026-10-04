import Foundation
import TandemProtocol

public enum PhotoServiceError: Error, Equatable, Sendable {
    /// A page request was already outstanding (the phone allows one).
    case pageInFlight
    /// The phone answered with a `PhotoError`.
    case failed(Tandem_V1_PhotoErrorReason)
    /// The session ended before the phone answered.
    case disconnected
}

/// The production ``PhotoService`` for one session (E41-05): sends `PhotoPage`, `ThumbRequest` and
/// `OriginalRequest` on FILES and suspends each caller until the matching `PhotoPageResult`,
/// `ThumbResult` or `PhotoError` arrives from ``FilesChannelRouter``. A page response carries no
/// request id, so correlation relies on the one-outstanding-page cap; thumbnails correlate by id.
/// Wrap in ``CachingPhotoService`` to add the on-disk thumbnail cache.
public actor SessionPhotoService: PhotoService {
    private let session: any TandemSession
    private var pagePending: CheckedContinuation<Tandem_V1_PhotoPageResult, Error>?
    private var thumbPending: [String: [CheckedContinuation<Data, Error>]] = [:]

    public init(session: any TandemSession) {
        self.session = session
    }

    public func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        guard pagePending == nil else { throw PhotoServiceError.pageInFlight }
        var request = Tandem_V1_PhotoPage()
        request.cursor = cursor
        request.limit = limit
        return try await withCheckedThrowingContinuation { continuation in
            pagePending = continuation
            Task { await self.send(.photoPage(request), failing: .page) }
        }
    }

    public func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data {
        var request = Tandem_V1_ThumbRequest()
        request.id = id
        request.maxPx = maxPx
        return try await withCheckedThrowingContinuation { continuation in
            thumbPending[id, default: []].append(continuation)
            Task { await self.send(.thumbRequest(request), failing: .thumb(id)) }
        }
    }

    /// "Select more on phone" has no wire message (photos.proto); the phone grows its own
    /// selection, so there is nothing to send.
    public func requestMorePhotos() async throws {}

    public func requestOriginal(id: String, transferId: String) async throws {
        var request = Tandem_V1_OriginalRequest()
        request.id = id
        request.transferID = transferId
        try await session.send(.files, payload: .originalRequest(request))
    }

    func handle(_ result: Tandem_V1_PhotoPageResult) {
        pagePending?.resume(returning: result)
        pagePending = nil
    }

    func handle(_ result: Tandem_V1_ThumbResult) {
        thumbPending.removeValue(forKey: result.id)?.forEach { $0.resume(returning: result.pngBytes) }
    }

    func handle(_ error: Tandem_V1_PhotoError) {
        switch error.kind {
        case .page:
            pagePending?.resume(throwing: PhotoServiceError.failed(error.reason))
            pagePending = nil
        case .thumb:
            thumbPending.removeValue(forKey: error.ref)?
                .forEach { $0.resume(throwing: PhotoServiceError.failed(error.reason)) }
        default:
            break
        }
    }

    /// Fails every outstanding request, called when the session ends.
    func cancelAll() {
        pagePending?.resume(throwing: PhotoServiceError.disconnected)
        pagePending = nil
        let thumbs = thumbPending
        thumbPending = [:]
        thumbs.values.joined().forEach { $0.resume(throwing: PhotoServiceError.disconnected) }
    }

    private enum Failed {
        case page
        case thumb(String)
    }

    private func send(_ payload: Tandem_V1_Envelope.OneOf_Payload, failing request: Failed) async {
        guard (try? await session.send(.files, payload: payload)) == nil else { return }
        switch request {
        case .page:
            pagePending?.resume(throwing: PhotoServiceError.disconnected)
            pagePending = nil
        case .thumb(let id):
            thumbPending.removeValue(forKey: id)?.forEach { $0.resume(throwing: PhotoServiceError.disconnected) }
        }
    }
}
