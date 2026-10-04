#if DEBUG
import FeatureFiles
import Foundation
import SwiftUI
import TandemProtocol

extension ScenarioView {
    /// A three-photo library the phone shares only partially (E41-05), so the limited-access
    /// banner shows without a phone.
    @MainActor
    static func makePhotoGridPartialAccessView() -> some View {
        PhotoGridView(viewModel: PhotoGridViewModel(service: SeededPartialAccessPhotoService()))
    }
}

private struct SeededPartialAccessPhotoService: PhotoService {
    func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        var result = Tandem_V1_PhotoPageResult()
        result.items = (0..<3).map { index in
            var meta = Tandem_V1_PhotoMeta()
            meta.id = "seeded-\(index)"
            return meta
        }
        result.access = .partial
        return result
    }

    func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data { Data() }

    func requestMorePhotos() async throws {}

    func requestOriginal(id: String, transferId: String) async throws {}
}
#endif
