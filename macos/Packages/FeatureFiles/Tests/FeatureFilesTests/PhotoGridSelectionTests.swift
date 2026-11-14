import Testing
import TandemProtocol

@testable import FeatureFiles

@MainActor
struct PhotoGridSelectionTests {
    private func loadedViewModel(service: FakePhotoService) async -> PhotoGridViewModel {
        let viewModel = PhotoGridViewModel(service: service, makeTransferID: { "t" })
        await viewModel.loadFirstPage()
        return viewModel
    }

    @Test func photoGridVm_toggleSelection_selectsThenDeselects() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<5, nextCursor: "")])
        let viewModel = await loadedViewModel(service: service)

        viewModel.toggleSelection(id: "photo-2")
        #expect(viewModel.selectedIds == ["photo-2"])
        #expect(viewModel.isSelected(id: "photo-2"))

        viewModel.toggleSelection(id: "photo-2")
        #expect(viewModel.selectedIds.isEmpty)
        #expect(!viewModel.isSelected(id: "photo-2"))
    }

    @Test func photoGridVm_downloadSelected_requestsEachSelectedOriginalInGridOrderAndClearsSelection() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<5, nextCursor: "")])
        let viewModel = await loadedViewModel(service: service)
        viewModel.toggleSelection(id: "photo-3")
        viewModel.toggleSelection(id: "photo-1")

        await viewModel.downloadSelected()

        let requests = await service.originalRequests
        #expect(requests.map(\.id) == ["photo-1", "photo-3"])
        #expect(viewModel.selectedIds.isEmpty)
        #expect(viewModel.downloadStates["photo-1"] == .downloading)
        #expect(viewModel.downloadStates["photo-3"] == .downloading)
    }

    @Test func photoGridVm_downloadSelectedWithNothingSelected_requestsNothing() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<3, nextCursor: "")])
        let viewModel = await loadedViewModel(service: service)

        await viewModel.downloadSelected()

        #expect(await service.originalRequests.isEmpty)
    }

    @Test func photoGridVm_morePagesRemain_totalCountIsUnknown() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<100, nextCursor: "c1")])
        let viewModel = await loadedViewModel(service: service)

        #expect(viewModel.totalCount == nil)
        #expect(viewModel.items.count == 100)
    }

    @Test func photoGridVm_lastPageLoaded_totalCountIsLoadedCount() async {
        let service = FakePhotoService(pages: [FakePhotoService.page(ids: 0..<24, nextCursor: "")])
        let viewModel = await loadedViewModel(service: service)

        #expect(viewModel.totalCount == 24)
    }
}
