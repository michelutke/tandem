import CryptoKit
import Foundation
import Testing
import TandemStore
import TandemTestSupport
@testable import FeatureFiles
@testable import TandemProtocol

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private struct FixedFreeSpace: FreeSpaceProvider {
    func availableBytes(at destination: URL) -> UInt64 { 1 << 40 }
}

private struct SilentPrompts: AcceptPromptPresenter {
    let responses = AsyncStream<AcceptPromptResponse> { _ in }
    func present(offerId: String, displayName: String, size: UInt64) async {}
    func remove(offerId: String) async {}
}

struct RouterHarness {
    let session = FakeTandemSession()
    let recorder = OutcomeRecorder()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let destination: URL
    let staging: URL
    let acceptFlow: AcceptFlow
    let receiver: FileReceiver
    let transfers: SessionFileTransferService
    let router: FilesChannelRouter
    let senderClock = ManualTestClock()

    init(autoAccept: Bool) throws {
        destination = root.appendingPathComponent("Tandem", isDirectory: true)
        staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        acceptFlow = AcceptFlow(
            session: session, freeSpace: FixedFreeSpace(), presenter: SilentPrompts(), clock: ManualTestClock(),
            settings: AcceptSettings(autoAcceptEnabled: autoAccept), destination: destination
        )
        receiver = FileReceiver(
            session: session, directories: TransferDirectories(destination: destination, staging: staging),
            sink: FileHandleSink(), peer: "peer-a", now: { Date(timeIntervalSince1970: 0) }, progress: recorder
        )
        transfers = SessionFileTransferService(
            session: session, scheduler: FilesScheduler(session: session), progress: recorder,
            makeTransferId: { "out-1" }, clock: senderClock
        )
        router = FilesChannelRouter(
            acceptFlow: acceptFlow, receiver: receiver, transfers: transfers,
            photos: SessionPhotoService(session: session)
        )
    }

    func offer(id: String, name: String, data: Data) -> Tandem_V1_FileOffer {
        var offer = Tandem_V1_FileOffer()
        offer.id = id
        offer.name = name
        offer.size = UInt64(data.count)
        offer.sha256 = Data(SHA256.hash(data: data))
        return offer
    }

    func chunk(id: String, data: Data) -> Tandem_V1_FileChunk {
        var chunk = Tandem_V1_FileChunk()
        chunk.id = id
        chunk.seq = 0
        chunk.offset = 0
        chunk.data = data
        return chunk
    }

    func sentPayloads() async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await session.sent.map(\.payload)
    }
}

private final class RecordingTransfer: FileTransferService, @unchecked Sendable {
    let isConnected = true
    private let lock = NSLock()
    private var starts: [URL] = []
    private var handlers: [@Sendable () -> Void] = []
    private var accepting = true

    var started: [URL] { lock.withLock { starts } }

    func startOffer(for url: URL) async {}

    func startOffer(for url: URL, onEnded: @escaping @Sendable () -> Void) async -> Bool {
        lock.withLock {
            guard accepting else { return false }
            starts.append(url)
            handlers.append(onEnded)
            return true
        }
    }

    func setAccepting(_ value: Bool) {
        lock.withLock { accepting = value }
    }

    func endAll() {
        lock.withLock { handlers }.forEach { $0() }
    }
}

@Suite("SendRequestAgentLifecycle")
struct SendRequestAgentLifecycleTests {
    private struct QueueFixture {
        let root: URL
        let queue: SendRequestQueue
        let file: URL
    }

    private func makeQueue() throws -> QueueFixture {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let queue = SendRequestQueue(groupRoot: root.appendingPathComponent("group"))
        return QueueFixture(root: root, queue: queue, file: file)
    }

    @Test
    func sendRequestAgent_drainCalledTwice_offersEachCopyOnce() async throws {
        let fixture = try makeQueue()
        let (root, queue, file) = (fixture.root, fixture.queue, fixture.file)
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(files: [file])
        let transfer = RecordingTransfer()
        let agent = SendRequestAgent(queue: queue, transfer: transfer)

        let first = await agent.drain()
        let second = await agent.drain()

        #expect(first == 1)
        #expect(second == 0)
        #expect(transfer.started.count == 1)
    }

    @Test
    func sendRequestAgent_transferEnded_removesCopyFromQueue() async throws {
        let fixture = try makeQueue()
        let (root, queue, file) = (fixture.root, fixture.queue, fixture.file)
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(files: [file])
        let transfer = RecordingTransfer()
        let agent = SendRequestAgent(queue: queue, transfer: transfer)
        await agent.drain()
        let copy = try #require(transfer.started.first)

        transfer.endAll()

        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(queue.dequeue().isEmpty)
    }

    @Test
    func sendRequestAgent_offerNotStarted_copyKeptAndReofferedOnNextDrain() async throws {
        let fixture = try makeQueue()
        let (root, queue, file) = (fixture.root, fixture.queue, fixture.file)
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(files: [file])
        let transfer = RecordingTransfer()
        transfer.setAccepting(false)
        let agent = SendRequestAgent(queue: queue, transfer: transfer)

        let refused = await agent.drain()
        transfer.setAccepting(true)
        let retried = await agent.drain()

        #expect(refused == 0)
        #expect(retried == 1)
        #expect(transfer.started.count == 1)
    }

    @Test
    func sessionFileTransfer_offerAfterSessionEnded_notStartedNoSenderRegistered() async throws {
        let harness = try RouterHarness(autoAccept: false)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let file = harness.root.appendingPathComponent("a.bin")
        try Data("x".utf8).write(to: file)
        await harness.transfers.sessionEnded()

        let started = await harness.transfers.startOffer(for: file, onEnded: {})

        #expect(!started)
        #expect(await harness.sentPayloads().isEmpty)
        #expect(harness.recorder.events.isEmpty)
    }

    @Test
    func activeFileTransfer_detached_offerNotStarted() async throws {
        let active = ActiveFileTransferService()

        let started = await active.startOffer(for: URL(fileURLWithPath: "/tmp/none"), onEnded: {})

        #expect(!started)
    }
}
