import CryptoKit
import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private struct AmpleSpace: FreeSpaceProvider {
    func availableBytes(at destination: URL) -> UInt64 { UInt64.max }
}

private actor SilentPresenter: AcceptPromptPresenter {
    nonisolated let responses = AsyncStream<AcceptPromptResponse> { _ in }
    private(set) var promptCount = 0

    func present(offerId: String, displayName: String, size: UInt64) { promptCount += 1 }
    func remove(offerId: String) {}
}

@Suite @MainActor struct OriginalDownloadTransferTests {
    @Test func originalDownload_fixturePhoto12MiB_savedByteIdenticalOnMac() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = root.appendingPathComponent("Tandem", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = Data((0..<(12 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) })
        let session = FakeTandemSession()
        let presenter = SilentPresenter()
        let flow = AcceptFlow(
            session: session,
            freeSpace: AmpleSpace(),
            presenter: presenter,
            clock: ManualTestClock(),
            settings: AcceptSettings(autoAcceptEnabled: false),
            destination: destination
        )
        let receiver = FileReceiver(
            session: session,
            directories: TransferDirectories(destination: destination, staging: staging),
            sink: FileHandleSink()
        )
        let photos = FakePhotoService()
        let viewModel = PhotoGridViewModel(service: photos, offerExpecting: flow, makeTransferID: { "orig1" })

        await viewModel.download(id: "photo-0")
        let transferId = try #require(await photos.originalRequests.first?.transferId)

        var offer = Tandem_V1_FileOffer()
        offer.id = transferId
        offer.name = "photo-0.jpg"
        offer.size = UInt64(fixture.count)
        offer.sha256 = Data(SHA256.hash(data: fixture))
        await flow.handle(offer: offer)
        #expect(await presenter.promptCount == 0)
        await receiver.begin(offer: offer)

        let chunkSize = 262_144
        for (seq, start) in stride(from: 0, to: fixture.count, by: chunkSize).enumerated() {
            var chunk = Tandem_V1_FileChunk()
            chunk.id = transferId
            chunk.seq = UInt64(seq)
            chunk.offset = UInt64(start)
            chunk.data = fixture.subdata(in: start..<min(start + chunkSize, fixture.count))
            await receiver.handle(chunk: chunk)
        }
        var complete = Tandem_V1_FileComplete()
        complete.id = transferId
        await receiver.handle(complete: complete)
        await viewModel.originalTransferFinished(transferId: transferId)

        let saved = try Data(contentsOf: destination.appendingPathComponent("photo-0.jpg"))
        #expect(saved == fixture)
        #expect(await viewModel.downloadStates["photo-0"] == .downloaded)
    }
}
