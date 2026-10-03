import Foundation
import TandemProtocol

/// The photo browser's feature-local seam over the FILES channel (backlog E41-05, SPEC.md
/// "Photos"): one call per `PhotoPage`, `ThumbRequest`, and "select more on phone" request. The
/// composition root adapts `TandemSession` to this; the view model is tested against a fake.
public protocol PhotoService: Sendable {
    func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult
    func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data
    func requestMorePhotos() async throws
    func requestOriginal(id: String, transferId: String) async throws
}

/// Receiver-side seam for E41-10: tells the accept flow which `FileOffer` ids answer one of our
/// `OriginalRequest`s so they are accepted without a prompt.
public protocol OriginalOfferExpecting: Sendable {
    func expectOriginal(transferId: String) async
    func forgetOriginal(transferId: String) async
}
