import Foundation
import Testing
import TandemProtocol
@testable import FeatureFiles

struct ActivePhotoServiceTests {
    @Test
    func activePhotoService_noSessionAttached_throwsDisconnected() async {
        let service = ActivePhotoService()

        await #expect(throws: PhotoServiceError.disconnected) {
            _ = try await service.fetchPage(cursor: "", limit: 10)
        }
    }

    @Test
    func activePhotoService_attached_routesToSessionService() async throws {
        let base = FakePhotoService(thumbnailBytes: Data([1, 2]))
        let service = ActivePhotoService()
        service.attach(base)

        let bytes = try await service.fetchThumbnail(id: "p1", maxPx: 64)

        #expect(bytes == Data([1, 2]))
        #expect(await base.thumbRequests.map(\.id) == ["p1"])
    }

    @Test
    func activePhotoService_detached_throwsDisconnected() async {
        let service = ActivePhotoService()
        service.attach(FakePhotoService())
        service.detach()

        await #expect(throws: PhotoServiceError.disconnected) {
            try await service.requestMorePhotos()
        }
    }
}
