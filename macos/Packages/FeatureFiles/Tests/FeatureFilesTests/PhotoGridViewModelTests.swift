import Testing
import TandemProtocol

@testable import FeatureFiles

@MainActor
struct PhotoGridViewModelTests {
    private func loadedViewModel(service: FakePhotoService) async -> PhotoGridViewModel {
        let viewModel = PhotoGridViewModel(service: service)
        await viewModel.loadFirstPage()
        return viewModel
    }

    @Test func photoGridVm_lastVisibleIndexWithin50OfLoaded_requestsNextPage() async {
        let service = FakePhotoService(pages: [
            FakePhotoService.page(ids: 0..<100, nextCursor: "c1"),
            FakePhotoService.page(ids: 100..<200, nextCursor: "")
        ])
        let viewModel = await loadedViewModel(service: service)

        await viewModel.loadNextPageIfNeeded(lastVisibleIndex: 49)
        #expect(await service.pageRequests.count == 1)

        await viewModel.loadNextPageIfNeeded(lastVisibleIndex: 50)
        let requests = await service.pageRequests
        #expect(requests.count == 2)
        #expect(requests[1].cursor == "c1")
        #expect(requests[1].limit == 100)
        #expect(viewModel.items.count == 200)
    }

    @Test func photoGridVm_pageInFlight_noDuplicateRequest() async {
        let service = FakePhotoService(pages: [
            FakePhotoService.page(ids: 0..<100, nextCursor: "c1"),
            FakePhotoService.page(ids: 100..<200, nextCursor: "c2")
        ])
        let viewModel = await loadedViewModel(service: service)
        await service.holdPageRequests()

        let inFlight = Task { await viewModel.loadNextPageIfNeeded(lastVisibleIndex: 60) }
        while await service.pageRequests.count < 2 { await Task.yield() }
        await viewModel.loadNextPageIfNeeded(lastVisibleIndex: 90)
        await service.releasePageRequests()
        await inFlight.value

        #expect(await service.pageRequests.count == 2)
    }

    @Test func photoGridVm_visibleRange_thumbRequestsOnlyVisiblePlusOneViewport() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<100, nextCursor: "c1")])
        let viewModel = await loadedViewModel(service: service)

        await viewModel.loadThumbnails(visible: 30...39)

        let requested = Set(await service.thumbRequests.map(\.id))
        #expect(requested == Set((20...49).map { "photo-\($0)" }))
        #expect(await service.thumbRequests.allSatisfy { $0.maxPx == 256 })
        #expect(viewModel.thumbnails.count == 30)
    }

    @Test func photoGridVm_visibleRangeRepeated_thumbNotRequestedTwice() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<100, nextCursor: "c1")])
        let viewModel = await loadedViewModel(service: service)

        await viewModel.loadThumbnails(visible: 0...9)
        await viewModel.loadThumbnails(visible: 0...9)

        #expect(await service.thumbRequests.count == 20)
    }

    @Test func photoGridVm_partialAccess_showsLimitedBannerAndSelectMoreSendsRequest() async {
        let service = FakePhotoService(pages: [
            FakePhotoService.page(ids: 0..<3, nextCursor: "", access: .partial)
        ])
        let viewModel = await loadedViewModel(service: service)

        #expect(viewModel.showsLimitedAccessBanner)
        await viewModel.selectMoreOnPhone()
        #expect(await service.moreRequests == 1)
    }

    @Test func photoGridVm_fullAccess_noLimitedBanner() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<3, nextCursor: "")])
        let viewModel = await loadedViewModel(service: service)

        #expect(!viewModel.showsLimitedAccessBanner)
    }
}

private actor RecordingOfferExpecting: OriginalOfferExpecting {
    private(set) var expected: [String] = []
    private(set) var forgotten: [String] = []
    func expectOriginal(transferId: String) { expected.append(transferId) }
    func forgetOriginal(transferId: String) { forgotten.append(transferId) }
}

private struct DownloadError: Error {}

@MainActor
struct PhotoGridViewModelDownloadTests {
    private func makeViewModel(
        service: FakePhotoService,
        expecting: RecordingOfferExpecting
    ) -> PhotoGridViewModel {
        PhotoGridViewModel(service: service, offerExpecting: expecting, makeTransferID: { "xfer-1" })
    }

    @Test func originalDownload_download_sendsRequestWithFreshTransferIdAndRecordsPending() async {
        let service = FakePhotoService()
        let expecting = RecordingOfferExpecting()
        let viewModel = makeViewModel(service: service, expecting: expecting)

        await viewModel.download(id: "photo-3")

        let requests = await service.originalRequests
        #expect(requests.map(\.id) == ["photo-3"])
        #expect(requests.map(\.transferId) == ["xfer-1"])
        #expect(await expecting.expected == ["xfer-1"])
        #expect(viewModel.downloadStates["photo-3"] == .downloading)
    }

    @Test func originalDownload_photoErrorForTransferId_itemStateFailed() async {
        let service = FakePhotoService()
        let expecting = RecordingOfferExpecting()
        let viewModel = makeViewModel(service: service, expecting: expecting)
        await viewModel.download(id: "photo-3")

        var error = Tandem_V1_PhotoError()
        error.kind = .original
        error.ref = "photo-3"
        await viewModel.photoErrorReceived(error)

        #expect(viewModel.downloadStates["photo-3"] == .failed)
        #expect(await expecting.forgotten == ["xfer-1"])
    }

    @Test func originalDownload_thumbErrorForSamePhoto_ignored() async {
        let service = FakePhotoService()
        let expecting = RecordingOfferExpecting()
        let viewModel = makeViewModel(service: service, expecting: expecting)
        await viewModel.download(id: "photo-3")

        var error = Tandem_V1_PhotoError()
        error.kind = .thumb
        error.ref = "photo-3"
        await viewModel.photoErrorReceived(error)

        #expect(viewModel.downloadStates["photo-3"] == .downloading)
    }

    @Test func originalDownload_requestSendThrows_itemStateFailed() async {
        let service = FakePhotoService()
        await service.setOriginalRequestError(DownloadError())
        let expecting = RecordingOfferExpecting()
        let viewModel = makeViewModel(service: service, expecting: expecting)

        await viewModel.download(id: "photo-3")

        #expect(viewModel.downloadStates["photo-3"] == .failed)
        #expect(await expecting.forgotten == ["xfer-1"])
    }

    @Test func originalDownload_transferFinished_itemStateDownloaded() async {
        let service = FakePhotoService()
        let viewModel = makeViewModel(service: service, expecting: RecordingOfferExpecting())
        await viewModel.download(id: "photo-3")

        viewModel.originalTransferFinished(transferId: "xfer-1")

        #expect(viewModel.downloadStates["photo-3"] == .downloaded)
    }
}
