import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private let chunkSize = 262_144

@MainActor
struct TransferProgressWiringTests {
    private func makeFile(bytes: Int) throws -> (source: LocalFileChunkSource, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("f.bin")
        try Data(count: bytes).write(to: url)
        return (LocalFileChunkSource(url: url), directory)
    }

    private func settle(until condition: () async -> Bool) async {
        for _ in 0..<5000 {
            if await condition() { return }
            await Task.yield()
        }
    }

    @Test
    func macTransferProgress_senderReportsBytes_rowAdvances() async throws {
        let (source, directory) = try makeFile(bytes: 4 * chunkSize)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ManualTestClock()
        let center = TransferProgressCenter(clock: clock)
        let session = FakeTandemSession()
        let sender = FileSender(
            id: "t1",
            name: "f.bin",
            mime: "application/octet-stream",
            source: source,
            session: session,
            scheduler: FilesScheduler(session: session),
            progress: center
        )

        await sender.start()
        #expect(center.rows.map(\.id) == ["t1"])
        #expect(center.rows.first?.progress.percent == 0)

        var accepted = Tandem_V1_FileAccept()
        accepted.id = "t1"
        await sender.handle(accept: accepted)
        await settle { await sender.state == .completed }

        #expect(center.rows.isEmpty)
    }

    @Test
    func macTransferProgress_senderChunks_reportCumulativeBytes() async throws {
        let (source, directory) = try makeFile(bytes: 3 * chunkSize + 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = RecordingProgress()
        let session = FakeTandemSession()
        let sender = FileSender(
            id: "t1",
            name: "f.bin",
            mime: "application/octet-stream",
            source: source,
            session: session,
            scheduler: FilesScheduler(session: session),
            progress: recorder
        )

        await sender.start()
        var accepted = Tandem_V1_FileAccept()
        accepted.id = "t1"
        await sender.handle(accept: accepted)
        await settle { await sender.state == .completed }

        let total = Int64(3 * chunkSize + 1)
        #expect(recorder.events.first == "began t1 \(total)")
        let delivered = recorder.events.filter { $0.hasPrefix("delivered") }
        #expect(delivered == ["delivered t1 \(chunkSize)", "delivered t1 \(2 * chunkSize)",
                              "delivered t1 \(3 * chunkSize)", "delivered t1 \(total)"])
        #expect(recorder.events.last == "ended t1")
    }

    @Test
    func macTransferProgress_rowCancel_callsSenderCancelAndRemovesRow() async throws {
        let (source, directory) = try makeFile(bytes: 4 * chunkSize)
        defer { try? FileManager.default.removeItem(at: directory) }
        let center = TransferProgressCenter(clock: ManualTestClock())
        let session = FakeTandemSession()
        let sender = FileSender(
            id: "t1",
            name: "f.bin",
            mime: "application/octet-stream",
            source: source,
            session: session,
            scheduler: FilesScheduler(session: session),
            progress: center
        )
        await sender.start()

        await center.rows.first?.cancel()
        await settle { await sender.isCancelled }

        #expect(await sender.isCancelled)
    }
}

private final class RecordingProgress: TransferProgressReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] { lock.withLock { recorded } }

    func began(id: String, name: String, totalBytes: Int64, cancel: @escaping @Sendable () async -> Void) async {
        lock.withLock { recorded.append("began \(id) \(totalBytes)") }
    }

    func delivered(id: String, bytes: Int64) async {
        lock.withLock { recorded.append("delivered \(id) \(bytes)") }
    }

    func ended(id: String) async {
        lock.withLock { recorded.append("ended \(id)") }
    }
}
