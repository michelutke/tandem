import CryptoKit
import Foundation
import Testing
import TandemProtocol
@testable import FeatureFiles

private let chunkSize = 262_144
private let mebibyte = 1 << 20

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
        var block = Data(count: mebibyte)
        for index in 0..<mebibyte { block[index] = UInt8(truncatingIfNeeded: index &* 31 &+ index >> 8) }
        var bytes = Data()
        while bytes.count < size { bytes.append(block) }
        content = bytes.prefix(size)
        sourceURL = root.appendingPathComponent("source.bin")
        try content.write(to: sourceURL)
    }

    var partURL: URL { directories.staging.appendingPathComponent("t1.part") }

    var offer: Tandem_V1_FileOffer {
        var offer = Tandem_V1_FileOffer()
        offer.id = "t1"
        offer.name = "big.bin"
        offer.size = UInt64(content.count)
        offer.sha256 = Data(SHA256.hash(data: content))
        return offer
    }

    func receiver(
        session: FakeTandemSession,
        peer: String = "peer-a",
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
    ) -> FileReceiver {
        FileReceiver(session: session, directories: directories, sink: FileHandleSink(), peer: peer, now: now)
    }

    func sender(session: FakeTandemSession) -> FileSender {
        FileSender(
            id: "t1", name: "big.bin", mime: "application/octet-stream",
            source: LocalFileChunkSource(url: sourceURL), session: session,
            scheduler: FilesScheduler(session: session)
        )
    }

    /// First connection: the receiver stores `chunks` whole chunks, then the link is severed.
    func severed(afterChunks chunks: Int, strayBytes: Int = 0) async throws {
        let receiver = receiver(session: FakeTandemSession())
        await receiver.begin(offer: offer)
        for seq in 0..<chunks {
            var chunk = Tandem_V1_FileChunk()
            chunk.id = "t1"
            chunk.seq = UInt64(seq)
            chunk.offset = UInt64(seq * chunkSize)
            chunk.data = content[(seq * chunkSize)..<((seq + 1) * chunkSize)]
            await receiver.handle(chunk: chunk)
        }
        let handle = try FileHandle(forWritingTo: partURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0xEE, count: strayBytes))
        try handle.close()
    }

    func destinationContent() -> Data? {
        try? Data(contentsOf: directories.destination.appendingPathComponent("big.bin"))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private func resumeRequest(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> Tandem_V1_FileResumeRequest? {
    payloads.lazy.compactMap { if case .fileResumeRequest(let request) = $0 { request } else { nil } }.first
}

private func cancel(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> Tandem_V1_FileCancel? {
    payloads.lazy.compactMap { if case .fileCancel(let cancel) = $0 { cancel } else { nil } }.first
}

private func reject(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> Tandem_V1_FileReject? {
    payloads.lazy.compactMap { if case .fileReject(let reject) = $0 { reject } else { nil } }.first
}

private func settle(until condition: () async -> Bool) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
}

private func deliver(_ payloads: [Tandem_V1_Envelope.OneOf_Payload], to receiver: FileReceiver) async {
    for payload in payloads {
        switch payload {
        case .fileChunk(let chunk): await receiver.handle(chunk: chunk)
        case .fileComplete(let complete): await receiver.handle(complete: complete)
        case .fileCancel(let cancel): await receiver.handle(cancel: cancel)
        default: break
        }
    }
}

private func resumeAndFinish(
    rig: Rig, receiverSession: FakeTandemSession, receiver: FileReceiver
) async throws -> [Tandem_V1_FileChunk] {
    let request = try #require(resumeRequest(await receiverSession.sent.map(\.payload)))
    let senderSession = FakeTandemSession()
    let sender = rig.sender(session: senderSession)
    await sender.handle(resume: request)
    await settle { await senderSession.sent.contains { if case .fileComplete = $0.payload { true } else { false } } }
    let payloads = await senderSession.sent.map(\.payload)
    await deliver(payloads, to: receiver)
    return payloads.compactMap { if case .fileChunk(let chunk) = $0 { chunk } else { nil } }
}

@Suite("Resume")
struct FileResumeTests {
    @Test
    func macosResume_severedAt40MiB_resumeRequestFromOffset40MiB() async throws {
        let rig = try Rig(size: 64 * mebibyte)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 160, strayBytes: 1_000)
        let session = FakeTandemSession()
        let receiver = rig.receiver(session: session)

        let resumed = await receiver.resumeRetained()
        let request = resumeRequest(await session.sent.map(\.payload))

        #expect(resumed == ["t1"])
        #expect(request?.id == "t1")
        #expect(request?.fromOffset == UInt64(40 * mebibyte))
        let senderSession = FakeTandemSession()
        let sender = rig.sender(session: senderSession)
        await sender.handle(resume: try #require(request))
        await settle { await senderSession.sent.contains { if case .fileChunk = $0.payload { true } else { false } } }
        let first = await senderSession.sent.compactMap { frame -> Tandem_V1_FileChunk? in
            if case .fileChunk(let chunk) = frame.payload { chunk } else { nil }
        }.first
        #expect(first?.seq == UInt64(40 * mebibyte / chunkSize))
        #expect(first?.offset == UInt64(40 * mebibyte))
    }

    @Test
    func macosResume_resumedTransfer_destinationSha256MatchesSource() async throws {
        let rig = try Rig(size: 3 * chunkSize + 100)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 2, strayBytes: 77)
        let session = FakeTandemSession()
        let receiver = rig.receiver(session: session)
        await receiver.resumeRetained()

        let sent = try await resumeAndFinish(rig: rig, receiverSession: session, receiver: receiver)

        #expect(sent.map(\.seq) == [2, 3])
        #expect(rig.destinationContent().map { Data(SHA256.hash(data: $0)) } == Data(SHA256.hash(data: rig.content)))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: rig.directories.staging.path)) == [])
        #expect(await session.sent.count == 1)
    }

    @Test
    func macosResume_corruptedPrefixOnDisk_hashMismatchCancelAndPartDeleted() async throws {
        let rig = try Rig(size: 3 * chunkSize + 100)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 2)
        let handle = try FileHandle(forWritingTo: rig.partURL)
        try handle.write(contentsOf: Data([0xFF]))
        try handle.close()
        let session = FakeTandemSession()
        let receiver = rig.receiver(session: session)
        await receiver.resumeRetained()

        _ = try await resumeAndFinish(rig: rig, receiverSession: session, receiver: receiver)

        #expect(cancel(await session.sent.map(\.payload))?.reason == .hashMismatch)
        #expect(rig.destinationContent() == nil)
        #expect(!FileManager.default.fileExists(atPath: rig.partURL.path))
    }

    @Test
    func macosResume_unknownTransferId_fileRejectUnknownTransfer() async throws {
        let session = FakeTandemSession()
        let responder = FileResumeResponder(session: session)
        var request = Tandem_V1_FileResumeRequest()
        request.id = "nope"
        request.fromOffset = 0

        await responder.handle(resume: request)

        let reply = reject(await session.sent.map(\.payload))
        #expect(reply?.id == "nope")
        #expect(reply?.reason == .unknownTransfer)
    }

    @Test
    func macosResume_sourceDeletedBeforeResume_sourceUnavailableAndPartDeleted() async throws {
        let rig = try Rig(size: 3 * chunkSize + 100)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 2)
        let receiverSession = FakeTandemSession()
        let receiver = rig.receiver(session: receiverSession)
        await receiver.resumeRetained()
        try FileManager.default.removeItem(at: rig.sourceURL)
        let senderSession = FakeTandemSession()
        let sender = rig.sender(session: senderSession)
        let responder = FileResumeResponder(session: senderSession)
        await responder.register(id: "t1", sender: sender)

        await responder.handle(resume: try #require(resumeRequest(await receiverSession.sent.map(\.payload))))
        await deliver(await senderSession.sent.map(\.payload), to: receiver)

        #expect(cancel(await senderSession.sent.map(\.payload))?.reason == .sourceUnavailable)
        #expect(!FileManager.default.fileExists(atPath: rig.partURL.path))
    }

    @Test
    func macosResume_offsetBeyondSourceSize_protocolViolationAndNoChunks() async throws {
        let rig = try Rig(size: chunkSize)
        defer { rig.cleanUp() }
        let session = FakeTandemSession()
        let sender = rig.sender(session: session)
        var request = Tandem_V1_FileResumeRequest()
        request.id = "t1"
        request.fromOffset = UInt64(2 * chunkSize)

        await sender.handle(resume: request)

        let payloads = await session.sent.map(\.payload)
        #expect(cancel(payloads)?.reason == .protocolViolation)
        #expect(payloads.count == 1)
    }

    @Test
    func macosResume_partOlderThan24h_deletedAndNoResumeRequest() async throws {
        let rig = try Rig(size: 3 * chunkSize)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 1)
        let written = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: rig.partURL.path)
        let session = FakeTandemSession()
        let receiver = rig.receiver(session: session, now: { written.addingTimeInterval(24 * 3600 + 1) })

        let resumed = await receiver.resumeRetained()

        #expect(resumed.isEmpty)
        #expect(await session.sent.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.partURL.path))
    }

    @Test
    func macosResume_partExactly24hOld_stillResumed() async throws {
        let rig = try Rig(size: 3 * chunkSize)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 1)
        let written = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: rig.partURL.path)
        let session = FakeTandemSession()
        let receiver = rig.receiver(session: session, now: { written.addingTimeInterval(24 * 3600) })

        #expect(await receiver.resumeRetained() == ["t1"])
        #expect(resumeRequest(await session.sent.map(\.payload))?.fromOffset == UInt64(chunkSize))
    }

    @Test
    func macosResume_differentPeer_noResumeRequestAndPartKept() async throws {
        let rig = try Rig(size: 3 * chunkSize)
        defer { rig.cleanUp() }
        try await rig.severed(afterChunks: 1)
        let session = FakeTandemSession()
        let receiver = rig.receiver(session: session, peer: "peer-b")

        #expect(await receiver.resumeRetained().isEmpty)
        #expect(await session.sent.isEmpty)
        #expect(FileManager.default.fileExists(atPath: rig.partURL.path))
    }
}
