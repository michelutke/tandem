import CryptoKit
import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private struct FixedFreeSpace: FreeSpaceProvider {
    func availableBytes(at destination: URL) -> UInt64 { 1 << 40 }
}

private struct SilentPrompts: AcceptPromptPresenter {
    let responses = AsyncStream<AcceptPromptResponse> { _ in }
    func present(offerId: String, displayName: String, size: UInt64) async {}
    func remove(offerId: String) async {}
}

private struct Harness {
    let session = FakeTandemSession()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let acceptFlow: AcceptFlow
    let receiver: FileReceiver
    let transfers: SessionFileTransferService
    let photos: SessionPhotoService
    let router: FilesChannelRouter
    let destination: URL

    init(autoAccept: Bool) throws {
        destination = root.appendingPathComponent("Tandem", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        acceptFlow = AcceptFlow(
            session: session, freeSpace: FixedFreeSpace(), presenter: SilentPrompts(), clock: ManualTestClock(),
            settings: AcceptSettings(autoAcceptEnabled: autoAccept), destination: destination
        )
        receiver = FileReceiver(
            session: session, directories: TransferDirectories(destination: destination, staging: staging),
            sink: FileHandleSink(), peer: "peer-a", now: { Date(timeIntervalSince1970: 0) }
        )
        transfers = SessionFileTransferService(
            session: session, scheduler: FilesScheduler(session: session), makeTransferId: { "out-1" }
        )
        photos = SessionPhotoService(session: session)
        router = FilesChannelRouter(acceptFlow: acceptFlow, receiver: receiver, transfers: transfers, photos: photos)
    }

    func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    func sentPayloads() async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await session.sent.map(\.payload)
    }
}

private func offer(id: String, data: Data) -> Tandem_V1_FileOffer {
    var offer = Tandem_V1_FileOffer()
    offer.id = id
    offer.name = "a.txt"
    offer.size = UInt64(data.count)
    offer.sha256 = Data(SHA256.hash(data: data))
    return offer
}

private func chunk(id: String, data: Data) -> Tandem_V1_FileChunk {
    var chunk = Tandem_V1_FileChunk()
    chunk.id = id
    chunk.seq = 0
    chunk.offset = 0
    chunk.data = data
    return chunk
}

@Suite struct FilesChannelRouterTests {
    @Test func filesChannelRouter_acceptedOffer_chunksWrittenAndFileDelivered() async throws {
        let harness = try Harness(autoAccept: true)
        let data = Data("hello".utf8)

        await harness.router.route(.fileOffer(offer(id: "t1", data: data)))
        await harness.router.route(.fileChunk(chunk(id: "t1", data: data)))
        var complete = Tandem_V1_FileComplete()
        complete.id = "t1"
        await harness.router.route(.fileComplete(complete))

        let delivered = harness.destination.appendingPathComponent("a.txt")
        #expect(try Data(contentsOf: delivered) == data)
        #expect(await harness.acceptFlow.isActive(id: "t1") == false)
    }

    @Test func filesChannelRouter_chunkForOfferNeverAccepted_dropped() async throws {
        let harness = try Harness(autoAccept: false)
        let data = Data("hello".utf8)

        await harness.router.route(.fileOffer(offer(id: "t1", data: data)))
        await harness.router.route(.fileChunk(chunk(id: "t1", data: data)))

        #expect(await harness.receiver.hasTransfer(id: "t1") == false)
    }

    @Test func filesChannelRouter_acceptForOutgoingOffer_sendsChunksAndComplete() async throws {
        let harness = try Harness(autoAccept: false)
        try FileManager.default.createDirectory(at: harness.root, withIntermediateDirectories: true)
        let file = harness.root.appendingPathComponent("out.txt")
        try Data("payload".utf8).write(to: file)

        await harness.transfers.startOffer(for: file)
        var accept = Tandem_V1_FileAccept()
        accept.id = "out-1"
        await harness.router.route(.fileAccept(accept))
        await harness.settle()

        let payloads = await harness.sentPayloads()
        #expect(payloads.contains { if case .fileOffer = $0 { true } else { false } })
        #expect(payloads.contains { if case .fileChunk = $0 { true } else { false } })
        #expect(payloads.contains { if case .fileComplete = $0 { true } else { false } })
    }

    @Test func filesChannelRouter_photoPageResult_resumesPendingFetch() async throws {
        let harness = try Harness(autoAccept: false)
        let photos = harness.photos
        let fetch = Task { try await photos.fetchPage(cursor: "", limit: 100) }
        await harness.settle()

        var result = Tandem_V1_PhotoPageResult()
        result.nextCursor = "next"
        await harness.router.route(.photoPageResult(result))

        #expect(try await fetch.value.nextCursor == "next")
    }

    @Test func filesChannelRouter_sessionEnded_failsOutstandingThumbnail() async throws {
        let harness = try Harness(autoAccept: false)
        let photos = harness.photos
        let fetch = Task { try await photos.fetchThumbnail(id: "p1", maxPx: 256) }
        await harness.settle()

        await harness.router.sessionEnded()

        await #expect(throws: PhotoServiceError.disconnected) { try await fetch.value }
    }
}
