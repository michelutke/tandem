import Foundation
import Testing
import TandemProtocol
import TandemStore
import TandemTestSupport
@testable import FeatureFiles

private final class CancellationSensitiveHistory: TransferHistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [TransferRecord] = []

    var appended: [TransferRecord] { lock.withLock { records } }

    func append(_ record: TransferRecord) async throws {
        if Task.isCancelled { throw CancellationError() }
        lock.withLock { records.append(record) }
    }

    func list() async throws -> [TransferRecord] { appended }

    func clear() async throws {}
}

@MainActor
struct FileSenderHistoryTests {
    private func settle(until condition: () async -> Bool) async {
        for _ in 0..<5000 {
            if await condition() { return }
            await Task.yield()
        }
    }

    @Test
    func macosSender_graceExpiryWithCancellationSensitiveHistory_completedTransferIsPersisted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("f.bin")
        try Data(count: 10).write(to: url)
        let clock = ManualTestClock()
        let history = CancellationSensitiveHistory()
        let center = TransferProgressCenter(clock: clock, history: history)
        let session = FakeTandemSession()
        let sender = FileSender(
            id: "t1", name: "f.bin", mime: "application/octet-stream",
            source: LocalFileChunkSource(url: url), session: session,
            scheduler: FilesScheduler(session: session), progress: center, clock: clock
        )

        await sender.start()
        var accepted = Tandem_V1_FileAccept()
        accepted.id = "t1"
        await sender.handle(accept: accepted)
        await settle { await sender.state == .completed }
        await settle { clock.advance(by: FileSender.completionGrace); return center.rows.isEmpty }
        await settle { !history.appended.isEmpty }

        #expect(history.appended.map(\.id) == ["t1"])
    }
}
