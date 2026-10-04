import CryptoKit
import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private actor RecordingReceivedPresenter: ReceivedFilePresenter {
    struct Presented: Equatable { let displayName: String; let destination: URL }
    private(set) var presented: [Presented] = []
    nonisolated let activations: AsyncStream<URL>
    private nonisolated let continuation: AsyncStream<URL>.Continuation

    init() {
        (activations, continuation) = AsyncStream.makeStream()
    }

    func present(displayName: String, destination: URL) {
        presented.append(Presented(displayName: displayName, destination: destination))
    }

    nonisolated func activate(_ url: URL) {
        continuation.yield(url)
        continuation.finish()
    }
}

private actor RecordingRevealer: FileRevealer {
    private(set) var revealed: [URL] = []
    func reveal(_ url: URL) { revealed.append(url) }
}

private struct Harness {
    let session = FakeTandemSession()
    let presenter = RecordingReceivedPresenter()
    let revealer = RecordingRevealer()
    let root: URL
    let destination: URL
    let receiver: FileReceiver
    let notifier: ReceivedFileNotifier

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        destination = root.appendingPathComponent("Tandem", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        notifier = ReceivedFileNotifier(presenter: presenter, revealer: revealer)
        receiver = FileReceiver(
            session: session,
            directories: TransferDirectories(destination: destination, staging: staging),
            sink: FileHandleSink(), peer: "peer-a",
            now: { Date(timeIntervalSince1970: 0) }, notifier: notifier
        )
    }

    func transfer(name: String = "report.pdf", content: Data, sha256: Data? = nil) async {
        var offer = Tandem_V1_FileOffer()
        offer.id = "t1"
        offer.name = name
        offer.size = UInt64(content.count)
        offer.sha256 = sha256 ?? Data(SHA256.hash(data: content))
        await receiver.begin(offer: offer)
        var chunk = Tandem_V1_FileChunk()
        chunk.id = "t1"
        chunk.seq = 0
        chunk.offset = 0
        chunk.data = content
        await receiver.handle(chunk: chunk)
        var complete = Tandem_V1_FileComplete()
        complete.id = "t1"
        await receiver.handle(complete: complete)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Suite struct ReceivedNotificationTests {
    private let content = Data("hello".utf8)

    @Test func macosReceivedNotification_receiveSucceeded_presentedWithSavedName() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await harness.transfer(content: content)
        await harness.transfer(content: content)
        let presented = await harness.presenter.presented
        #expect(presented.map(\.displayName) == ["report.pdf", "report (1).pdf"])
        #expect(presented.last?.destination == harness.destination.appendingPathComponent("report (1).pdf"))
    }

    @Test func macosReceivedNotification_activated_revealsDestinationUrl() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let url = harness.destination.appendingPathComponent("report.pdf")
        harness.presenter.activate(url)
        await harness.notifier.runActivations()
        #expect(await harness.revealer.revealed == [url])
    }

    @Test func macosReceivedNotification_hashMismatch_nothingPresented() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await harness.transfer(content: content, sha256: Data(SHA256.hash(data: Data("other".utf8))))
        #expect(await harness.presenter.presented.isEmpty)
    }

    @Test func macosReceivedNotification_userCancelled_nothingPresented() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        var offer = Tandem_V1_FileOffer()
        offer.id = "t1"
        offer.name = "report.pdf"
        offer.size = 5
        offer.sha256 = Data(SHA256.hash(data: content))
        await harness.receiver.begin(offer: offer)
        await harness.receiver.cancel(id: "t1")
        #expect(await harness.presenter.presented.isEmpty)
    }
}
