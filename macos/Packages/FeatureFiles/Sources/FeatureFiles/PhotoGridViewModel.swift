import Foundation
import Observation
import TandemProtocol

/// Drives the photo grid (backlog E41-05, PRD F-7.4, UC-17): pages in `PhotoPage`s of 100 when
/// the last visible index comes within 50 of the loaded count (one page request at a time, per
/// the phone's 1-outstanding-`PhotoPage` cap), and requests 256 px thumbnails only for visible
/// cells plus one viewport above and below (at most 8 in flight, the phone's `ThumbRequest` cap).
/// Cursors are opaque -- only ever echoed back from `nextCursor`.
@MainActor
@Observable
public final class PhotoGridViewModel {
    static let pageLimit: UInt32 = 100
    static let prefetchDistance = 50
    static let thumbMaxPx: UInt32 = 256
    static let maxOutstandingThumbs = 8

    public private(set) var items: [Tandem_V1_PhotoMeta] = []
    public private(set) var access: Tandem_V1_PhotoAccess = .unspecified
    public private(set) var thumbnails: [String: Data] = [:]
    public private(set) var loadFailed = false

    public var showsLimitedAccessBanner: Bool { access == .partial }

    @ObservationIgnored private let service: any PhotoService
    @ObservationIgnored private var nextCursor = ""
    @ObservationIgnored private var hasMorePages = true
    @ObservationIgnored private var pageInFlight = false
    @ObservationIgnored private var requestedThumbIDs: Set<String> = []
    @ObservationIgnored private var desiredThumbRange: ClosedRange<Int>?
    @ObservationIgnored private var thumbLoaderRunning = false

    public init(service: any PhotoService) {
        self.service = service
    }

    public func loadFirstPage() async {
        await loadPage()
    }

    public func visibleRangeChanged(_ visible: ClosedRange<Int>) async {
        async let page: Void = loadNextPageIfNeeded(lastVisibleIndex: visible.upperBound)
        async let thumbs: Void = loadThumbnails(visible: visible)
        _ = await (page, thumbs)
    }

    public func loadNextPageIfNeeded(lastVisibleIndex: Int) async {
        guard lastVisibleIndex >= items.count - Self.prefetchDistance else { return }
        await loadPage()
    }

    public func loadThumbnails(visible: ClosedRange<Int>) async {
        desiredThumbRange = visible
        guard !thumbLoaderRunning else { return }
        thumbLoaderRunning = true
        defer { thumbLoaderRunning = false }
        while true {
            let wanted = unrequestedThumbIDs()
            if wanted.isEmpty { return }
            requestedThumbIDs.formUnion(wanted)
            await fetchThumbnails(wanted)
        }
    }

    public func selectMoreOnPhone() async {
        try? await service.requestMorePhotos()
    }

    private func unrequestedThumbIDs() -> [String] {
        guard let visible = desiredThumbRange, !items.isEmpty else { return [] }
        let viewport = visible.count
        let lower = max(0, visible.lowerBound - viewport)
        let upper = min(items.count - 1, visible.upperBound + viewport)
        guard lower <= upper else { return [] }
        return items[lower...upper].map(\.id).filter { !requestedThumbIDs.contains($0) }
    }

    private func fetchThumbnails(_ ids: [String]) async {
        await withTaskGroup(of: (String, Data?).self) { group in
            var remaining = ids[...]
            func addNext() {
                guard let id = remaining.popFirst() else { return }
                group.addTask { [service] in
                    (id, try? await service.fetchThumbnail(id: id, maxPx: Self.thumbMaxPx))
                }
            }
            for _ in 0..<Self.maxOutstandingThumbs { addNext() }
            for await (id, data) in group {
                if let data { thumbnails[id] = data }
                addNext()
            }
        }
    }

    private func loadPage() async {
        guard hasMorePages, !pageInFlight else { return }
        pageInFlight = true
        defer { pageInFlight = false }
        do {
            let result = try await service.fetchPage(cursor: nextCursor, limit: Self.pageLimit)
            items.append(contentsOf: result.items)
            access = result.access
            nextCursor = result.nextCursor
            hasMorePages = !result.nextCursor.isEmpty
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
