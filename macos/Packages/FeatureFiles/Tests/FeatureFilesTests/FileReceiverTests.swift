import CryptoKit
import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private struct FailingSink: FileSink {
    let failAfterBytes: Int
    let error: any Error

    func create(at url: URL) throws -> any FileSinkHandle {
        FailingHandle(inner: try FileHandleSink().create(at: url), remaining: failAfterBytes, error: error)
    }

    func reopen(at url: URL) throws -> any FileSinkHandle {
        FailingHandle(inner: try FileHandleSink().reopen(at: url), remaining: failAfterBytes, error: error)
    }
}

private final class FailingHandle: FileSinkHandle {
    let inner: any FileSinkHandle
    var remaining: Int
    let error: any Error

    init(inner: any FileSinkHandle, remaining: Int, error: any Error) {
        self.inner = inner
        self.remaining = remaining
        self.error = error
    }

    func write(_ data: Data) throws {
        guard data.count <= remaining else { throw error }
        remaining -= data.count
        try inner.write(data)
    }

    func close() throws { try inner.close() }
}

private struct Harness {
    let session = FakeTandemSession()
    let root: URL
    let directories: TransferDirectories
    let receiver: FileReceiver

    init(sink: any FileSink = FileHandleSink()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = root.appendingPathComponent("Tandem", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        directories = TransferDirectories(destination: destination, staging: staging)
        receiver = FileReceiver(
            session: session, directories: directories, sink: sink, peer: "peer-a",
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func listing(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func sentPayloads() async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await session.sent.map(\.payload)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private func offer(name: String = "report.pdf", content: Data, sha256: Data? = nil) -> Tandem_V1_FileOffer {
    var offer = Tandem_V1_FileOffer()
    offer.id = "t1"
    offer.name = name
    offer.size = UInt64(content.count)
    offer.sha256 = sha256 ?? Data(SHA256.hash(data: content))
    return offer
}

private func chunk(seq: UInt64, offset: UInt64? = nil, data: Data) -> Tandem_V1_FileChunk {
    var chunk = Tandem_V1_FileChunk()
    chunk.id = "t1"
    chunk.seq = seq
    chunk.offset = offset ?? seq * 262_144
    chunk.data = data
    return chunk
}

private func complete() -> Tandem_V1_FileComplete {
    var message = Tandem_V1_FileComplete()
    message.id = "t1"
    return message
}

private func cancel(_ reason: Tandem_V1_TransferReason) -> Tandem_V1_Envelope.OneOf_Payload {
    var message = Tandem_V1_FileCancel()
    message.id = "t1"
    message.reason = reason
    return .fileCancel(message)
}

private let twoChunks = Data(repeating: 7, count: 262_144) + Data(repeating: 9, count: 100)

private func receive(_ content: Data, into harness: Harness, offerValue: Tandem_V1_FileOffer) async {
    await harness.receiver.begin(offer: offerValue)
    var seq: UInt64 = 0
    var index = 0
    while index < content.count {
        let end = min(index + 262_144, content.count)
        await harness.receiver.handle(chunk: chunk(seq: seq, data: content[index..<end]))
        seq += 1
        index = end
    }
    await harness.receiver.handle(complete: complete())
}

@Suite struct FileReceiverTests {
    @Test func macosReceiver_matchingHash_fileInDestinationAndPartDeleted() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await receive(twoChunks, into: harness, offerValue: offer(content: twoChunks))
        #expect(harness.listing(harness.directories.destination) == ["report.pdf"])
        #expect(harness.listing(harness.directories.staging).isEmpty)
        let saved = try Data(contentsOf: harness.directories.destination.appendingPathComponent("report.pdf"))
        #expect(saved == twoChunks)
        #expect(await harness.sentPayloads().isEmpty)
    }

    @Test func macosReceiver_midTransfer_destinationHasNoEntry() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await harness.receiver.begin(offer: offer(content: twoChunks))
        await harness.receiver.handle(chunk: chunk(seq: 0, data: twoChunks.prefix(262_144)))
        #expect(harness.listing(harness.directories.destination).isEmpty)
        #expect(harness.listing(harness.directories.staging) == ["t1.part"])
    }

    @Test func macosReceiver_hashMismatch_destinationEmptyPartDeletedAndRejectSent() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let wrong = Data(SHA256.hash(data: Data("other".utf8)))
        await receive(twoChunks, into: harness, offerValue: offer(content: twoChunks, sha256: wrong))
        #expect(harness.listing(harness.directories.destination).isEmpty)
        #expect(harness.listing(harness.directories.staging).isEmpty)
        #expect(await harness.sentPayloads() == [cancel(.hashMismatch)])
    }

    @Test func macosReceiver_enospcDuringWrite_partDeletedAndInsufficientSpaceCancelSent() async throws {
        let sink = FailingSink(failAfterBytes: 262_144, error: POSIXError(.ENOSPC))
        let harness = try Harness(sink: sink)
        defer { harness.cleanUp() }
        await receive(twoChunks, into: harness, offerValue: offer(content: twoChunks))
        #expect(harness.listing(harness.directories.destination).isEmpty)
        #expect(harness.listing(harness.directories.staging).isEmpty)
        #expect(await harness.sentPayloads() == [cancel(.insufficientSpace)])
    }

    @Test func macosReceiver_existingSameName_savedWithOneSuffixOriginalUntouched() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let original = Data("original".utf8)
        let existing = harness.directories.destination.appendingPathComponent("report.pdf")
        try original.write(to: existing)
        await receive(twoChunks, into: harness, offerValue: offer(content: twoChunks))
        #expect(harness.listing(harness.directories.destination) == ["report (1).pdf", "report.pdf"])
        #expect(try Data(contentsOf: existing) == original)
    }

    @Test func macosReceiver_chunkBeyondOfferedSize_protocolViolationCancelAndPartDeleted() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let content = Data(repeating: 1, count: 10)
        await harness.receiver.begin(offer: offer(content: content))
        await harness.receiver.handle(chunk: chunk(seq: 0, data: Data(repeating: 1, count: 11)))
        #expect(harness.listing(harness.directories.staging).isEmpty)
        #expect(harness.listing(harness.directories.destination).isEmpty)
        #expect(await harness.sentPayloads() == [cancel(.protocolViolation)])
    }

    @Test func macosReceiver_outOfOrderChunk_protocolViolationCancelAndPartDeleted() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await harness.receiver.begin(offer: offer(content: twoChunks))
        await harness.receiver.handle(chunk: chunk(seq: 1, data: twoChunks.suffix(100)))
        #expect(harness.listing(harness.directories.staging).isEmpty)
        #expect(await harness.sentPayloads() == [cancel(.protocolViolation)])
    }

    @Test func macosReceiver_completeBeforeAllBytes_protocolViolationCancelAndPartDeleted() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await harness.receiver.begin(offer: offer(content: twoChunks))
        await harness.receiver.handle(chunk: chunk(seq: 0, data: twoChunks.prefix(262_144)))
        await harness.receiver.handle(complete: complete())
        #expect(harness.listing(harness.directories.staging).isEmpty)
        #expect(harness.listing(harness.directories.destination).isEmpty)
        #expect(await harness.sentPayloads() == [cancel(.protocolViolation)])
    }

    @Test func macosReceiver_senderCancel_partDeletedNothingSent() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        await harness.receiver.begin(offer: offer(content: twoChunks))
        var message = Tandem_V1_FileCancel()
        message.id = "t1"
        message.reason = .userCancelled
        await harness.receiver.handle(cancel: message)
        #expect(harness.listing(harness.directories.staging).isEmpty)
        #expect(await harness.sentPayloads().isEmpty)
    }

    @Test func macosReceiver_traversalName_savedUnderSanitizedNameInsideDestination() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let content = Data("x".utf8)
        await receive(content, into: harness, offerValue: offer(name: "../../evil.sh", content: content))
        #expect(harness.listing(harness.directories.destination) == ["evil.sh"])
        #expect(harness.listing(harness.root) == ["Tandem", "staging"])
    }

    @Test func macosReceiver_unsafeTransferId_invalidNameRejectNothingStaged() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        var unsafe = offer(content: Data())
        unsafe.id = "../x"
        await harness.receiver.begin(offer: unsafe)
        var message = Tandem_V1_FileReject()
        message.id = "../x"
        message.reason = .invalidName
        #expect(await harness.sentPayloads() == [.fileReject(message)])
        #expect(harness.listing(harness.directories.staging).isEmpty)
    }
}
