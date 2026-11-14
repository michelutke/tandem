import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private final class FakeEventSource: OriginalTransferEventSource, @unchecked Sendable {
    let continuation: AsyncStream<OriginalTransferEvent>.Continuation
    private let stream: AsyncStream<OriginalTransferEvent>

    init() {
        (stream, continuation) = AsyncStream<OriginalTransferEvent>.makeStream()
    }

    func originalTransferEvents() -> AsyncStream<OriginalTransferEvent> { stream }
}

private final class EndedRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var value: [String] { lock.withLock { recorded } }

    func append(_ entry: String) { lock.withLock { recorded.append(entry) } }
}

@Suite @MainActor struct OriginalTransferEventsTests {
    private func downloadingViewModel(
        source: FakeEventSource
    ) async -> (PhotoGridViewModel, Task<Void, Never>) {
        let viewModel = PhotoGridViewModel(
            service: FakePhotoService(), events: source, makeTransferID: { "orig1" }
        )
        await viewModel.download(id: "photo-0")
        let observer = Task { await viewModel.observeOriginalEvents() }
        return (viewModel, observer)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<5000 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test func photoGrid_finishedEvent_stateDownloaded() async {
        let source = FakeEventSource()
        let (viewModel, observer) = await downloadingViewModel(source: source)

        source.continuation.yield(.finished(transferId: "orig1"))
        await settle { viewModel.downloadStates["photo-0"] == .downloaded }
        observer.cancel()

        #expect(viewModel.downloadStates["photo-0"] == .downloaded)
    }

    @Test func photoGrid_failedEvent_stateFailed() async {
        let source = FakeEventSource()
        let (viewModel, observer) = await downloadingViewModel(source: source)

        source.continuation.yield(.failed(transferId: "orig1"))
        await settle { viewModel.downloadStates["photo-0"] == .failed }
        observer.cancel()

        #expect(viewModel.downloadStates["photo-0"] == .failed)
    }

    @Test func photoGrid_originalPhotoErrorEvent_stateFailed() async {
        let source = FakeEventSource()
        let (viewModel, observer) = await downloadingViewModel(source: source)
        var error = Tandem_V1_PhotoError()
        error.kind = .original
        error.ref = "photo-0"

        source.continuation.yield(.photoError(error))
        await settle { viewModel.downloadStates["photo-0"] == .failed }
        observer.cancel()

        #expect(viewModel.downloadStates["photo-0"] == .failed)
    }

    @Test func photoGrid_disconnectedEvent_everyPendingDownloadFailed() async {
        let source = FakeEventSource()
        let (viewModel, observer) = await downloadingViewModel(source: source)

        source.continuation.yield(.disconnected)
        await settle { viewModel.downloadStates["photo-0"] == .failed }
        observer.cancel()

        #expect(viewModel.downloadStates["photo-0"] == .failed)
    }

    @Test func activePhotoService_publishedEvent_everySubscriberReceivesIt() async {
        let service = ActivePhotoService()
        var first = service.originalTransferEvents().makeAsyncIterator()
        var second = service.originalTransferEvents().makeAsyncIterator()

        service.publish(.finished(transferId: "t1"))

        #expect(await first.next() == .finished(transferId: "t1"))
        #expect(await second.next() == .finished(transferId: "t1"))
    }

    @Test func activePhotoService_detach_publishesDisconnected() async {
        let service = ActivePhotoService()
        service.attach(FakePhotoService())
        var events = service.originalTransferEvents().makeAsyncIterator()

        service.detach()

        #expect(await events.next() == .disconnected)
    }

    @Test func sessionPhotoService_originalPhotoError_reportedToCallback() async {
        let reported = EndedRecorder()
        let service = SessionPhotoService(session: FakeTandemSession(), onOriginalError: { reported.append($0.ref) })
        var original = Tandem_V1_PhotoError()
        original.kind = .original
        original.ref = "photo-0"
        var thumb = Tandem_V1_PhotoError()
        thumb.kind = .thumb
        thumb.ref = "photo-1"

        await service.handle(original)
        await service.handle(thumb)

        #expect(reported.value == ["photo-0"])
    }

    @Test func endForwardingProgress_endedOutcome_forwardedWithId() async {
        let recorder = EndedRecorder()
        let progress = EndForwardingProgress(base: nil) { id, outcome in
            recorder.append("\(id) \(outcome == .completed)")
        }

        await progress.ended(id: "t1", outcome: .completed)
        await progress.ended(id: "t2", outcome: .cancelled)

        #expect(recorder.value == ["t1 true", "t2 false"])
    }
}
