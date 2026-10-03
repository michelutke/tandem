import Foundation
import Testing
@testable import FeatureFiles

private final class RecordingTransferService: FileTransferService, @unchecked Sendable {
    let isConnected: Bool
    private(set) var started: [URL] = []

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }

    func startOffer(for url: URL) async {
        started.append(url)
    }
}

private struct Fixture {
    let root: URL
    let queue: SendRequestQueue

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        queue = SendRequestQueue(groupRoot: root.appendingPathComponent("group"))
    }

    func makeFile(_ name: String, contents: String = "x") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct SendRequestQueueTests {
    @Test func sendRequestQueue_twoFilesEnqueued_agentStartsTwoOffersInOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let files = [try fixture.makeFile("a.txt"), try fixture.makeFile("b.txt")]
        try fixture.queue.enqueue(files: files)
        let transfer = RecordingTransferService()

        let started = await SendRequestAgent(queue: fixture.queue, transfer: transfer).drain()

        #expect(started == 2)
        #expect(transfer.started.map(\.lastPathComponent) == ["a.txt", "b.txt"])
    }

    @Test func sendRequestQueue_transferEnded_appGroupCopyDeleted() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let request = try fixture.queue.enqueue(files: [try fixture.makeFile("a.txt")])
        let transfer = RecordingTransferService()
        let agent = SendRequestAgent(queue: fixture.queue, transfer: transfer)
        await agent.drain()
        let copy = try #require(transfer.started.first)

        agent.transferEnded(copy: copy)

        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: request.path))
    }

    @Test func sendRequestQueue_symlinkEntry_rejectedNoOffer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try fixture.makeFile("secret.txt")
        let slot = fixture.queue.directory.appendingPathComponent("req/00")
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: slot.appendingPathComponent("link.txt"),
            withDestinationURL: target
        )
        let transfer = RecordingTransferService()

        let started = await SendRequestAgent(queue: fixture.queue, transfer: transfer).drain()

        #expect(started == 0)
        #expect(transfer.started.isEmpty)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func sendRequestQueue_entryResolvingOutsideQueueDir_rejectedNoOffer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: outside.appendingPathComponent("evil.txt"))
        let request = fixture.queue.directory.appendingPathComponent("req")
        try FileManager.default.createDirectory(at: request, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: request.appendingPathComponent("00"),
            withDestinationURL: outside
        )
        let transfer = RecordingTransferService()

        let started = await SendRequestAgent(queue: fixture.queue, transfer: transfer).drain()

        #expect(started == 0)
        #expect(transfer.started.isEmpty)
    }

    @Test func sendRequestQueue_nonRegularEntry_rejectedNoOffer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let nested = fixture.queue.directory.appendingPathComponent("req/00/folder")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let transfer = RecordingTransferService()

        let started = await SendRequestAgent(queue: fixture.queue, transfer: transfer).drain()

        #expect(started == 0)
    }

    @Test func sendRequestQueue_moreThanTwentyFiles_enqueueThrows() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.makeFile("a.txt")

        #expect(throws: SendRequestQueueError.invalidFileCount(21)) {
            try fixture.queue.enqueue(files: Array(repeating: file, count: 21))
        }
        #expect(throws: SendRequestQueueError.invalidFileCount(0)) {
            try fixture.queue.enqueue(files: [])
        }
    }

    @Test func sendRequestQueue_moreThanTwentySlotsOnDisk_rejectedNoOffer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let request = fixture.queue.directory.appendingPathComponent("req")
        for index in 0..<21 {
            let slot = request.appendingPathComponent(String(format: "%02d", index))
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: slot.appendingPathComponent("f.txt"))
        }
        let transfer = RecordingTransferService()

        let started = await SendRequestAgent(queue: fixture.queue, transfer: transfer).drain()

        #expect(started == 0)
    }

    @Test func sendRequestQueue_notConnected_queueLeftUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let request = try fixture.queue.enqueue(files: [try fixture.makeFile("a.txt")])
        let transfer = RecordingTransferService(isConnected: false)

        let started = await SendRequestAgent(queue: fixture.queue, transfer: transfer).drain()

        #expect(started == 0)
        #expect(FileManager.default.fileExists(atPath: request.path))
    }
}
