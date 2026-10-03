import CryptoKit
import Foundation
import Testing
import TandemProtocol
@testable import FeatureFiles

private let chunkSize = 262_144

private struct Rig {
    let root: URL
    let directories: TransferDirectories
    let sourceURL: URL
    let content: Data

    init(size: Int) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = root.appendingPathComponent("Tandem", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        directories = TransferDirectories(destination: destination, staging: staging)
        content = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) })
        sourceURL = root.appendingPathComponent("source.bin")
        try content.write(to: sourceURL)
    }

    var partURL: URL { directories.staging.appendingPathComponent("t1.part") }

    func receiver(session: FakeTandemSession) -> FileReceiver {
        FileReceiver(
            session: session, directories: directories, sink: FileHandleSink(), peer: "peer-a",
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func sender(session: any TandemSession) -> FileSender {
        FileSender(
            id: "t1", name: "big.bin", mime: "application/octet-stream",
            source: LocalFileChunkSource(url: sourceURL), session: session,
            scheduler: FilesScheduler(session: session)
        )
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private func settle(until condition: () async -> Bool) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
}

private func chunkCount(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> Int {
    payloads.filter { if case .fileChunk = $0 { true } else { false } }.count
}

private func firstOffer(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> Tandem_V1_FileOffer? {
    payloads.lazy.compactMap { if case .fileOffer(let offer) = $0 { offer } else { nil } }.first
}

private func cancelReason(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> Tandem_V1_TransferReason? {
    payloads.lazy.compactMap { if case .fileCancel(let cancel) = $0 { cancel.reason } else { nil } }.first
}

private func accept() -> Tandem_V1_FileAccept {
    var message = Tandem_V1_FileAccept()
    message.id = "t1"
    return message
}

/// Models an exhausted FILES credit window: after `window` chunks, the next chunk send suspends until `open()`.
private actor CreditGatedSession: TandemSession {
    private let inner = FakeTandemSession()
    private let window: Int
    private var chunksSent = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated var state: AsyncStream<ConnectionStateMachine.ConnectionState> { inner.state }

    init(window: Int) { self.window = window }

    var sent: [Tandem_V1_Envelope.OneOf_Payload] { get async { await inner.sent.map(\.payload) } }

    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        if case .fileChunk = payload {
            if chunksSent >= window, !isOpen {
                await withCheckedContinuation { waiters.append($0) }
            }
            chunksSent += 1
        }
        try await inner.send(channel, payload: payload)
    }

    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream { await inner.receive(channel) }

    func close() async { await inner.close() }

    var isBlocked: Bool { !waiters.isEmpty }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@Suite("FileCancel")
struct FileCancelTests {
    @Test
    func macosCancel_senderInitiated_noChunkAfterCancelAndReceiverPartDeleted() async throws {
        let rig = try Rig(size: 8 * chunkSize)
        defer { rig.cleanUp() }
        let senderSession = CreditGatedSession(window: 2)
        let receiver = rig.receiver(session: FakeTandemSession())
        let sender = rig.sender(session: senderSession)

        await sender.start()
        let offer = try #require(firstOffer(await senderSession.sent))
        await receiver.begin(offer: offer)
        await sender.handle(accept: accept())
        await settle { await senderSession.isBlocked }
        for case .fileChunk(let chunk) in await senderSession.sent { await receiver.handle(chunk: chunk) }
        #expect(FileManager.default.fileExists(atPath: rig.partURL.path))

        await sender.cancel()
        await senderSession.open()
        await settle { cancelReason(await senderSession.sent) != nil }

        let payloads = await senderSession.sent
        let cancelIndex = try #require(payloads.firstIndex { if case .fileCancel = $0 { true } else { false } })
        #expect(chunkCount(Array(payloads[cancelIndex...])) == 0)
        #expect(cancelReason(payloads) == .userCancelled)
        #expect(await sender.state == .cancelled(.userCancelled))

        for case .fileCancel(let cancel) in payloads { await receiver.handle(cancel: cancel) }
        #expect(!FileManager.default.fileExists(atPath: rig.partURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.directories.destination.path).isEmpty)
    }

    @Test
    func macosCancel_receiverInitiated_senderStopsWithinCreditWindow() async throws {
        let rig = try Rig(size: 8 * chunkSize)
        defer { rig.cleanUp() }
        let senderSession = CreditGatedSession(window: 2)
        let receiverSession = FakeTandemSession()
        let sender = rig.sender(session: senderSession)
        let receiver = rig.receiver(session: receiverSession)

        await sender.start()
        let offer = try #require(firstOffer(await senderSession.sent))
        await receiver.begin(offer: offer)
        await sender.handle(accept: accept())
        await settle { await senderSession.isBlocked }
        for case .fileChunk(let chunk) in await senderSession.sent { await receiver.handle(chunk: chunk) }

        await receiver.cancel(id: "t1")
        #expect(cancelReason(await receiverSession.sent.map(\.payload)) == .userCancelled)
        #expect(!FileManager.default.fileExists(atPath: rig.partURL.path))

        var cancel = Tandem_V1_FileCancel()
        cancel.id = "t1"
        cancel.reason = .userCancelled
        await sender.handle(cancel: cancel)
        await senderSession.open()
        for _ in 0..<2000 { await Task.yield() }

        #expect(chunkCount(await senderSession.sent) <= 3)
        #expect(await sender.nextFrame() == nil)
        #expect(await sender.state == .cancelled(.userCancelled))
    }

    @Test
    func macosCancel_resumeForCancelledId_fileRejectUnknownTransfer() async throws {
        let rig = try Rig(size: 2 * chunkSize)
        defer { rig.cleanUp() }
        let senderSession = FakeTandemSession()
        let sender = rig.sender(session: senderSession)
        let responder = FileResumeResponder(session: senderSession)
        await responder.register(id: "t1", sender: sender)
        await sender.start()
        await sender.handle(accept: accept())
        await sender.cancel()
        await settle { await senderSession.sent.contains { if case .fileCancel = $0.payload { true } else { false } } }
        let before = await senderSession.sent.count

        var request = Tandem_V1_FileResumeRequest()
        request.id = "t1"
        request.fromOffset = UInt64(chunkSize)
        await responder.handle(resume: request)

        let after = await senderSession.sent.map(\.payload).dropFirst(before)
        #expect(after.count == 1)
        guard case .fileReject(let reject)? = after.first else {
            Issue.record("expected FileReject")
            return
        }
        #expect(reject.id == "t1")
        #expect(reject.reason == .unknownTransfer)
    }
}
