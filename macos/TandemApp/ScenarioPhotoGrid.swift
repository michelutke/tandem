#if DEBUG
import FeatureFiles
import AppKit
import Foundation
import SwiftUI
import TandemProtocol

extension ScenarioView {
    /// A three-photo library the phone shares only partially (E41-05), so the limited-access
    /// banner shows without a phone.
    @MainActor
    static func makePhotoGridPartialAccessView() -> some View {
        ScenarioPhotoGridHost { SeededPartialAccessPhotoService() }
    }
}

/// Holds the grid's view model in `@State`: the scenario root re-evaluates its body, and a view
/// model built inline would restart loading every time.
private struct ScenarioPhotoGridHost<Service: PhotoService>: View {
    @State private var viewModel: PhotoGridViewModel

    init(service: () -> Service) {
        _viewModel = State(initialValue: PhotoGridViewModel(service: service()))
    }

    var body: some View {
        PhotoGridView(viewModel: viewModel)
    }
}

extension ScenarioView {
    /// A 10 000-photo library with synthetic 256 px thumbnails (E41-09).
    @MainActor
    static func makePhotoGrid10kView() -> some View {
        ScenarioPhotoGridHost { Seeded10kPhotoService() }
    }
}

private struct Seeded10kPhotoService: PhotoService {
    private static let total = 10_000
    private static let side = 256
    private static let thumbnail: Data = {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
        return bitmap?.representation(using: .png, properties: [:]) ?? Data()
    }()

    func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        let start = Int(cursor) ?? 0
        let end = min(start + Int(limit), Self.total)
        var result = Tandem_V1_PhotoPageResult()
        result.items = (start..<end).map { index in
            var meta = Tandem_V1_PhotoMeta()
            meta.id = "seeded-\(index)"
            return meta
        }
        result.nextCursor = end < Self.total ? String(end) : ""
        result.access = .full
        return result
    }

    func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data { Self.thumbnail }

    func requestMorePhotos() async throws {}

    func requestOriginal(id: String, transferId: String) async throws {}
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
