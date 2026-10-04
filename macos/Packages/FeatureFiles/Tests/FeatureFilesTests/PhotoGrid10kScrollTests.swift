import Foundation
import Testing
import TandemCrypto
import TandemProtocol
import TandemTestSupport

@testable import FeatureFiles

private actor TenKPhotoService: PhotoService {
    static let total = 10_000
    static let pageSize = 100

    private(set) var pageRequests = 0
    private(set) var thumbRequests = 0
    private(set) var maxInFlight = 0
    private(set) var outOfWindowRequests = 0
    private var inFlight = 0
    private var window: ClosedRange<Int> = 0...0
    private let thumbnail: Data

    init(thumbnail: Data) {
        self.thumbnail = thumbnail
    }

    func setWindow(_ window: ClosedRange<Int>) {
        self.window = window
    }

    func fetchPage(cursor: String, limit: UInt32) async throws -> Tandem_V1_PhotoPageResult {
        pageRequests += 1
        let start = Int(cursor) ?? 0
        let end = min(start + Int(limit), Self.total)
        return FakePhotoService.page(ids: start..<end, nextCursor: end < Self.total ? String(end) : "")
    }

    func fetchThumbnail(id: String, maxPx: UInt32) async throws -> Data {
        thumbRequests += 1
        if let index = Int(id.dropFirst("photo-".count)), !window.contains(index) { outOfWindowRequests += 1 }
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        await Task.yield()
        inFlight -= 1
        return thumbnail
    }

    func requestMorePhotos() async throws {}

    func requestOriginal(id: String, transferId: String) async throws {}
}

@MainActor
@Suite struct PhotoGrid10kScrollTests {
    private static let viewport = 10
    private static let capBytes = 4 * 1024 * 1024
    private static let thumbBytes = 64 * 1024
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let pngTrailer = Data([
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ])

    @MainActor private struct Scroll {
        let directory: URL
        let service: TenKPhotoService
        let viewModel: PhotoGridViewModel
        var maxDecoded = 0
        var maxDiskBytes = 0
        private var steps = 0
        private static let diskSampleInterval = 20
        var pageRequestsAtBottom = 0
        var pageRequestsAfterBack = 0

        init() async throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tandem-10k-scroll-test-\(UUID().uuidString)")
            let png = PhotoGrid10kScrollTests.pngSignature
                + Data(repeating: 0x01, count: PhotoGrid10kScrollTests.thumbBytes)
                + PhotoGrid10kScrollTests.pngTrailer
            service = TenKPhotoService(thumbnail: png)
            let cache = try ThumbnailCache(
                directory: directory,
                capBytes: PhotoGrid10kScrollTests.capBytes,
                now: FixedDateProvider(clock: ManualTestClock()).provider
            )
            let peer = try SpkiFingerprint(bytes: Data(repeating: 0x07, count: 32))
            viewModel = PhotoGridViewModel(service: CachingPhotoService(base: service, cache: cache, peer: peer))
        }

        mutating func scrollDownAndBackUp() async {
            await viewModel.loadFirstPage()
            var first = 0
            while first + viewport <= TenKPhotoService.total {
                await step(first...(first + viewport - 1))
                first += viewport
            }
            pageRequestsAtBottom = await service.pageRequests
            first = TenKPhotoService.total - viewport
            while first >= 0 {
                await step(first...(first + viewport - 1))
                first -= viewport
            }
            pageRequestsAfterBack = await service.pageRequests - pageRequestsAtBottom
        }

        private mutating func step(_ visible: ClosedRange<Int>) async {
            await service.setWindow(max(0, visible.lowerBound - viewport)...(visible.upperBound + viewport))
            await viewModel.visibleRangeChanged(visible)
            maxDecoded = max(maxDecoded, viewModel.thumbnails.count)
            steps += 1
            if steps.isMultiple(of: Self.diskSampleInterval) { maxDiskBytes = max(maxDiskBytes, diskBytes()) }
        }

        private var viewport: Int { PhotoGrid10kScrollTests.viewport }

        private func diskBytes() -> Int {
            let files = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            )
            var total = 0
            while let url = files?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
            }
            return total
        }
    }

    private static let sharedScroll = Task { @MainActor () throws -> Scroll in
        var scroll = try await Scroll()
        await scroll.scrollDownAndBackUp()
        try? FileManager.default.removeItem(at: scroll.directory)
        return scroll
    }

    private static func scrolled() async throws -> Scroll {
        try await sharedScroll.value
    }

    @Test func photoGrid10kScroll_everyStep_thumbRequestsAtMostVisiblePlusPrefetch() async throws {
        let scroll = try await Self.scrolled()

        #expect(await scroll.service.outOfWindowRequests == 0)
        #expect(await scroll.service.maxInFlight <= PhotoGridViewModel.maxOutstandingThumbs)
        #expect(await scroll.service.thumbRequests > 0)
    }

    @Test func photoGrid10kScroll_decodedThumbnails_neverExceed300() async throws {
        let scroll = try await Self.scrolled()

        #expect(scroll.maxDecoded > 0)
        #expect(scroll.maxDecoded <= 300)
    }

    @Test func photoGrid10kScroll_diskCache_neverExceedsFourMiBCap() async throws {
        let scroll = try await Self.scrolled()

        #expect(scroll.maxDiskBytes > 0)
        #expect(scroll.maxDiskBytes <= Self.capBytes)
    }

    @Test func photoGrid10kScroll_downAndBackUp_exactly100PageRequests() async throws {
        let scroll = try await Self.scrolled()

        #expect(scroll.pageRequestsAtBottom == TenKPhotoService.total / TenKPhotoService.pageSize)
        #expect(scroll.pageRequestsAfterBack == 0)
    }
}
