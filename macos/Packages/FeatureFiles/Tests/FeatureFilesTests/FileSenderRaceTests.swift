import Foundation
import Testing
import TandemProtocol
import TandemStore
import TandemTestSupport
@testable import FeatureFiles

private actor GatedSession: TandemSession {
    private let inner = FakeTandemSession()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private(set) var sendStarted = false

    nonisolated var state: AsyncStream<ConnectionStateMachine.ConnectionState> { inner.state }

    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        sendStarted = true
        if !open { await withCheckedContinuation { waiters.append($0) } }
        try await inner.send(channel, payload: payload)
    }

    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        await inner.receive(channel)
    }

    func close() async { await inner.close() }

    func openGate() {
        open = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private final class BlockingFirstEndProgress: TransferProgressReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var outcomeList: [TransferOutcome] = []
    private var pending: CheckedContinuation<Void, Never>?
    private var released = false

    var events: [String] { lock.withLock { recorded } }
    var outcomes: [TransferOutcome] { lock.withLock { outcomeList } }

    func began(
        id: String,
        name: String,
        totalBytes: Int64,
        direction: TransferDirection,
        cancel: @escaping @Sendable () async -> Void
    ) async {
        lock.withLock { recorded.append("began \(id)") }
    }

    func delivered(id: String, bytes: Int64) async {}

    func ended(id: String, outcome: TransferOutcome, savedFile: URL?) async {
        let isFirst = lock.withLock {
            recorded.append("ended \(id)")
            outcomeList.append(outcome)
            return outcomeList.count == 1
        }
        guard isFirst else { return }
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if released { return true }
                pending = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let continuation = lock.withLock {
            released = true
            let held = pending
            pending = nil
            return held
        }
        continuation?.resume()
    }
}

private func settle(until condition: () async -> Bool) async {
    for _ in 0..<5000 {
        if await condition() { return }
        await Task.yield()
    }
}

private func makeSource(in directory: URL) throws -> LocalFileChunkSource {
    let url = directory.appendingPathComponent("f.bin")
    try Data(count: 10).write(to: url)
    return LocalFileChunkSource(url: url)
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite("FileSenderRace")
struct FileSenderRaceTests {
    @Test
    func macosSender_sessionDropsWhileOfferIsBeingSent_rowIsEndedAfterItBegan() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GatedSession()
        let progress = BlockingFirstEndProgress()
        progress.release()
        let sender = FileSender(
            id: "t1", name: "f.bin", mime: "application/octet-stream",
            source: try makeSource(in: directory), session: session,
            scheduler: FilesScheduler(session: session), progress: progress
        )

        let starting = Task { await sender.start() }
        await settle { await session.sendStarted }
        await sender.disconnected()
        await session.openGate()
        await starting.value

        #expect(progress.events.last == "ended t1")
    }

    @Test
    func macosSender_cancelWhileCompletionIsBeingReported_endedReportedOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ManualTestClock()
        let session = FakeTandemSession()
        let progress = BlockingFirstEndProgress()
        let sender = FileSender(
            id: "t1", name: "f.bin", mime: "application/octet-stream",
            source: try makeSource(in: directory), session: session,
            scheduler: FilesScheduler(session: session), progress: progress, clock: clock
        )
        await sender.start()
        var accepted = Tandem_V1_FileAccept()
        accepted.id = "t1"
        await sender.handle(accept: accepted)
        await settle { await sender.state == .completed }
        await settle { clock.advance(by: FileSender.completionGrace); return !progress.outcomes.isEmpty }

        var cancel = Tandem_V1_FileCancel()
        cancel.id = "t1"
        cancel.reason = .hashMismatch
        await sender.handle(cancel: cancel)
        progress.release()
        for _ in 0..<200 { await Task.yield() }

        #expect(progress.outcomes == [.completed])
    }
}
