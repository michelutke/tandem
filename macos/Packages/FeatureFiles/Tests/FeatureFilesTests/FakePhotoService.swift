import Foundation
import TandemProtocol

@testable import FeatureFiles

actor FakePhotoService: PhotoService {
    private(set) var pageRequests: [(cursor: String, limit: UInt32)] = []
    private(set) var thumbRequests: [(id: String, maxPx: UInt32)] = []
    private(set) var moreRequests = 0
    private var pageResults: [Tandem_V1_PhotoPageResult]
    private var pageGate: CheckedContinuation<Void, Never>?
    private var gatePageRequests = false
    private let thumbnailBytes: Data?

    init(pages: [Tandem_V1_PhotoPageResult] = [], thumbnailBytes: Data? = nil) {
        pageResults = pages
        self.thumbnailBytes = thumbnailBytes
    }

    func holdPageRequests() {
        gatePageRequests = true
    }

    func releasePageRequests() {
        gatePageRequests = false
        pageGate?.resume()
        pageGate = nil
    }

    func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        pageRequests.append((cursor, limit))
        if gatePageRequests {
            await withCheckedContinuation { pageGate = $0 }
        }
        return pageResults.isEmpty ? Tandem_V1_PhotoPageResult() : pageResults.removeFirst()
    }

    func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data {
        thumbRequests.append((id, maxPx))
        return thumbnailBytes ?? Data(id.utf8)
    }

    func requestMorePhotos() async throws {
        moreRequests += 1
    }

    static func page(
        ids: Range<Int>,
        nextCursor: String,
        access: Tandem_V1_PhotoAccess = .full
    ) -> Tandem_V1_PhotoPageResult {
        var result = Tandem_V1_PhotoPageResult()
        result.items = ids.map { index in
            var meta = Tandem_V1_PhotoMeta()
            meta.id = "photo-\(index)"
            return meta
        }
        result.nextCursor = nextCursor
        result.access = access
        return result
    }
}
