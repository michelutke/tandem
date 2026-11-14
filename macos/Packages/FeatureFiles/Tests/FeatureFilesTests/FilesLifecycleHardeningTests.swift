import Foundation
import Testing
import TandemStore
import TandemTestSupport
@testable import FeatureFiles
@testable import TandemProtocol

private struct SendFailure: Error {}

private actor ControlledSession: TandemSession {
    private let inner = FakeTandemSession()
    private var gateOpen: Bool
    private var failing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(gateOpen: Bool = true) {
        self.gateOpen = gateOpen
    }

    nonisolated var state: AsyncStream<ConnectionStateMachine.ConnectionState> { inner.state }

    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        if !gateOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        if failing { throw SendFailure() }
        try await inner.send(channel, payload: payload)
    }

    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        await inner.receive(channel)
    }

    func close() async { await inner.close() }

    func failSends() { failing = true }

    func closeGate() { gateOpen = false }

    func openGate() {
        gateOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

final class OutcomeRecorder: TransferProgressReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var outcomeList: [TransferOutcome] = []

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

    func delivered(id: String, bytes: Int64) async {
        lock.withLock { recorded.append("delivered \(id) \(bytes)") }
    }

    func ended(id: String, outcome: TransferOutcome, savedFile: URL?) async {
        lock.withLock {
            recorded.append("ended \(id)")
            outcomeList.append(outcome)
        }
    }
}

private func settle(until condition: () async -> Bool) async {
    for _ in 0..<5000 {
        if await condition() { return }
        await Task.yield()
    }
}

private func isComplete(_ payload: Tandem_V1_Envelope.OneOf_Payload) -> Bool {
    if case .fileComplete = payload { true } else { false }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func advancePastGrace(_ clock: ManualTestClock) async {
    clock.advance(by: FileSender.completionGrace)
    for _ in 0..<50 { await Task.yield() }
}

private func accept(_ id: String) -> Tandem_V1_FileAccept {
    var message = Tandem_V1_FileAccept()
    message.id = id
    return message
}

@Suite("FilesLifecycleHardening")
struct FilesLifecycleHardeningTests {
    private func makeSender(
        directory: URL,
        session: any TandemSession,
        progress: any TransferProgressReporting,
        clock: any Clock<Duration> = ManualTestClock()
    ) throws -> FileSender {
        let url = directory.appendingPathComponent("empty.bin")
        try Data().write(to: url)
        return FileSender(
            id: "t1", name: "empty.bin", mime: "application/octet-stream",
            source: LocalFileChunkSource(url: url), session: session,
            scheduler: FilesScheduler(session: session), progress: progress, clock: clock
        )
    }

    @Test
    func macosSender_cancelAfterCompleteFrame_outcomeFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ControlledSession()
        let recorder = OutcomeRecorder()
        let sender = try makeSender(directory: directory, session: session, progress: recorder)
        await sender.start()
        await session.closeGate()
        await sender.handle(accept: accept("t1"))
        await settle { await sender.state == .completing }
        #expect(await sender.state == .completing)

        var cancel = Tandem_V1_FileCancel()
        cancel.id = "t1"
        cancel.reason = .hashMismatch
        await sender.handle(cancel: cancel)

        await session.openGate()
        for _ in 0..<200 { await Task.yield() }

        #expect(recorder.outcomes == [.failed(reason: String(describing: Tandem_V1_TransferReason.hashMismatch))])
        #expect(await sender.state == .cancelled(.hashMismatch))
    }

    @Test
    func macosSender_cancelWithinGraceAfterCompleteSent_outcomeFailedNotCompleted() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ManualTestClock()
        let recorder = OutcomeRecorder()
        let sender = try makeSender(
            directory: directory, session: ControlledSession(), progress: recorder, clock: clock
        )
        await sender.start()
        await sender.handle(accept: accept("t1"))
        await settle { await sender.state == .completed }
        #expect(recorder.outcomes.isEmpty)

        var cancel = Tandem_V1_FileCancel()
        cancel.id = "t1"
        cancel.reason = .hashMismatch
        await sender.handle(cancel: cancel)
        await advancePastGrace(clock)

        #expect(recorder.outcomes == [.failed(reason: String(describing: Tandem_V1_TransferReason.hashMismatch))])
        #expect(await sender.state == .cancelled(.hashMismatch))
    }

    @Test
    func macosSender_graceElapsedAfterCompleteSent_outcomeCompletedOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ManualTestClock()
        let recorder = OutcomeRecorder()
        let sender = try makeSender(
            directory: directory, session: ControlledSession(), progress: recorder, clock: clock
        )
        await sender.start()
        await sender.handle(accept: accept("t1"))
        await settle { await sender.state == .completed }
        #expect(recorder.outcomes.isEmpty)

        await settle(until: { await advancePastGrace(clock); return !recorder.outcomes.isEmpty })
        await advancePastGrace(clock)

        #expect(recorder.outcomes == [.completed])
    }

    @Test
    func macosSender_disconnectedWithinGraceAfterCompleteSent_outcomeCompleted() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = OutcomeRecorder()
        let sender = try makeSender(
            directory: directory, session: ControlledSession(), progress: recorder, clock: ManualTestClock()
        )
        await sender.start()
        await sender.handle(accept: accept("t1"))
        await settle { await sender.state == .completed }

        await sender.disconnected()

        #expect(recorder.outcomes == [.completed])
    }

    @Test
    func macosSender_sourceUnreadable_rowBeganThenEndedFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ControlledSession()
        let recorder = OutcomeRecorder()
        let sender = FileSender(
            id: "t1", name: "gone.bin", mime: "application/octet-stream",
            source: LocalFileChunkSource(url: directory.appendingPathComponent("gone.bin")), session: session,
            scheduler: FilesScheduler(session: session), progress: recorder
        )

        await sender.start()

        #expect(recorder.events == ["began t1", "ended t1"])
        #expect(recorder.outcomes == [.failed(reason: "source unreadable")])
    }

    @Test
    func macosSender_completeFrameSendFails_outcomeFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ControlledSession()
        let recorder = OutcomeRecorder()
        let sender = try makeSender(directory: directory, session: session, progress: recorder)
        await sender.start()
        await session.failSends()

        await sender.handle(accept: accept("t1"))
        await settle { await sender.state == .failed }

        #expect(recorder.outcomes == [.failed(reason: "send failed")])
    }

    @Test
    func macosSender_completeFrameSent_outcomeCompletedOnlyAfterSend() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ControlledSession()
        let recorder = OutcomeRecorder()
        let clock = ManualTestClock()
        let sender = try makeSender(directory: directory, session: session, progress: recorder, clock: clock)
        await sender.start()
        await session.closeGate()
        await sender.handle(accept: accept("t1"))
        for _ in 0..<200 { await Task.yield() }

        #expect(recorder.outcomes.isEmpty)

        await session.openGate()
        await settle { await sender.state == .completed }
        await settle { await advancePastGrace(clock); return !recorder.outcomes.isEmpty }
        #expect(recorder.outcomes == [.completed])
    }

    @Test
    func filesScheduler_sendThrows_streamNotifiedAndRowEnded() async {
        let session = ControlledSession()
        await session.failSends()
        let stream = NotifiedStream()

        await FilesScheduler(session: session).enqueue(stream: stream)
        await settle { await stream.failed }

        #expect(await stream.failed)
    }

    @Test
    func filesRouter_sessionEnded_endsActiveRowsAsFailed() async throws {
        let harness = try RouterHarness(autoAccept: true)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let incoming = harness.offer(id: "in-1", name: "a.txt", data: Data("hello".utf8))
        await harness.router.route(.fileOffer(incoming))
        await harness.router.route(.fileChunk(harness.chunk(id: "in-1", data: Data("he".utf8))))
        let outgoing = harness.root.appendingPathComponent("out.txt")
        try Data("payload".utf8).write(to: outgoing)
        await harness.transfers.startOffer(for: outgoing)

        await harness.router.sessionEnded()

        let ended = harness.recorder.events.filter { $0.hasPrefix("ended") }
        #expect(Set(ended) == ["ended in-1", "ended out-1"])
        #expect(harness.recorder.outcomes.allSatisfy { $0 == .failed(reason: "disconnected") })
        #expect(await harness.receiver.hasTransfer(id: "in-1") == false)
        #expect(FileManager.default.fileExists(atPath: harness.staging.appendingPathComponent("in-1.part").path))
    }

    @Test
    func filesRouter_zeroByteOfferThenComplete_fileSavedEmpty() async throws {
        let harness = try RouterHarness(autoAccept: true)
        defer { try? FileManager.default.removeItem(at: harness.root) }

        await harness.router.route(.fileOffer(harness.offer(id: "t0", name: "empty.txt", data: Data())))
        var complete = Tandem_V1_FileComplete()
        complete.id = "t0"
        await harness.router.route(.fileComplete(complete))

        let saved = harness.destination.appendingPathComponent("empty.txt")
        #expect(try Data(contentsOf: saved).isEmpty)
        #expect(await harness.acceptFlow.isActive(id: "t0") == false)
    }

    @Test
    func sessionFileTransfer_senderCompleted_removedFromRegistry() async throws {
        let harness = try RouterHarness(autoAccept: false)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let file = harness.root.appendingPathComponent("empty.bin")
        try Data().write(to: file)
        await harness.transfers.startOffer(for: file)
        await harness.transfers.handle(accept: accept("out-1"))
        await settle { await harness.sentPayloads().contains(where: isComplete) }
        for _ in 0..<500 { await Task.yield() }
        await advancePastGrace(harness.senderClock)

        var resume = Tandem_V1_FileResumeRequest()
        resume.id = "out-1"
        await harness.transfers.handle(resume: resume)

        let rejected = await harness.sentPayloads().contains {
            if case .fileReject(let reject) = $0 { reject.reason == .unknownTransfer } else { false }
        }
        #expect(rejected)
    }
}

private actor NotifiedStream: FilesFrameStream {
    private(set) var failed = false

    func nextFrame() async -> Tandem_V1_Envelope.OneOf_Payload? {
        var complete = Tandem_V1_FileComplete()
        complete.id = "s1"
        return .fileComplete(complete)
    }

    func sendFailed() async {
        failed = true
    }
}
