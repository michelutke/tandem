import Foundation
import Testing
import TandemProtocol
import TandemTestSupport
@testable import FeatureFiles

private let chunkSize = 262_144

private struct Fixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ name: String = "f.bin", bytes: Data) throws -> LocalFileChunkSource {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return LocalFileChunkSource(url: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FixedReader: FileChunkReader {
    let remaining: ReadBudget

    func read(upTo count: Int) throws -> Data {
        try remaining.take(upTo: count)
    }

    func seek(to offset: UInt64) throws {}
}

private final class ReadBudget: @unchecked Sendable {
    private var bytes: Int
    private let failWhenSpent: Bool

    init(bytes: Int, failWhenSpent: Bool) {
        self.bytes = bytes
        self.failWhenSpent = failWhenSpent
    }

    func take(upTo count: Int) throws -> Data {
        if bytes == 0 {
            if failWhenSpent { throw CocoaError(.fileReadUnknown) }
            return Data()
        }
        let served = min(count, bytes)
        bytes -= served
        return Data(count: served)
    }
}

private final class FlakySource: FileChunkSource, @unchecked Sendable {
    private let totalBytes: Int
    private var opened = 0

    init(totalBytes: Int) { self.totalBytes = totalBytes }

    func makeReader() throws -> any FileChunkReader {
        opened += 1
        if opened == 1 {
            return FixedReader(remaining: ReadBudget(bytes: totalBytes, failWhenSpent: false))
        }
        return FixedReader(remaining: ReadBudget(bytes: chunkSize, failWhenSpent: true))
    }
}

private func accept(_ id: String) -> Tandem_V1_FileAccept {
    var message = Tandem_V1_FileAccept()
    message.id = id
    return message
}

private func settle(until condition: () async -> Bool) async {
    for _ in 0..<5000 {
        if await condition() { return }
        await Task.yield()
    }
}

private func chunks(_ payloads: [Tandem_V1_Envelope.OneOf_Payload]) -> [Tandem_V1_FileChunk] {
    payloads.compactMap { if case .fileChunk(let chunk) = $0 { chunk } else { nil } }
}

private func isComplete(_ payload: Tandem_V1_Envelope.OneOf_Payload) -> Bool {
    if case .fileComplete = payload { true } else { false }
}

@Suite("FileSender")
struct FileSenderTests {
    private func makeSender(
        source: any FileChunkSource,
        session: any TandemSession
    ) -> FileSender {
        FileSender(
            id: "t1",
            name: "f.bin",
            mime: "application/octet-stream",
            source: source,
            session: session,
            scheduler: FilesScheduler(session: session)
        )
    }

    @Test
    func macosSender_tenMiBPlusOneByteFile_sends41ContiguousChunksThenComplete() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let size = 10 * (1 << 20) + 1
        let session = FakeTandemSession()
        let sender = makeSender(source: try fixture.file(bytes: Data(count: size)), session: session)

        await sender.start()
        await sender.handle(accept: accept("t1"))
        await settle { await session.sent.contains { isComplete($0.payload) } }

        let payloads = await session.sent.map(\.payload)
        let sentChunks = chunks(payloads)
        #expect(sentChunks.count == 41)
        #expect(sentChunks.map(\.seq) == Array(0..<41))
        #expect(sentChunks.map(\.offset) == (0..<41).map { UInt64($0 * chunkSize) })
        #expect(sentChunks.last?.data.count == 1)
        #expect(payloads.filter(isComplete).count == 1)
        #expect(payloads.last.map(isComplete) == true)
        #expect(await sender.state == .completed)
    }

    @Test
    func macosSender_abcFixture_offerCarriesKnownSha256() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = FakeTandemSession()
        let sender = makeSender(source: try fixture.file(bytes: Data("abc".utf8)), session: session)

        await sender.start()

        guard case .fileOffer(let offer)? = await session.sent.first?.payload else {
            Issue.record("expected FileOffer first")
            return
        }
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(offer.sha256.map { String(format: "%02x", $0) }.joined() == expected)
        #expect(offer.size == 3)
        #expect(await sender.state == .offered)
    }

    @Test
    func macosSender_zeroByteFile_offerThenCompleteWithNoChunks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = FakeTandemSession()
        let sender = makeSender(source: try fixture.file(bytes: Data()), session: session)

        await sender.start()
        await sender.handle(accept: accept("t1"))
        await settle { await session.sent.contains { isComplete($0.payload) } }

        let payloads = await session.sent.map(\.payload)
        guard case .fileOffer(let offer)? = payloads.first else {
            Issue.record("expected FileOffer first")
            return
        }
        #expect(offer.size == 0)
        #expect(chunks(payloads).isEmpty)
        #expect(payloads.count == 2)
        #expect(isComplete(payloads[1]))
    }

    @Test
    func macosSender_fileRejectReceived_zeroChunksSentAndStateRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = FakeTandemSession()
        let sender = makeSender(source: try fixture.file(bytes: Data(count: 1000)), session: session)

        await sender.start()
        var reject = Tandem_V1_FileReject()
        reject.id = "t1"
        reject.reason = .declined
        await sender.handle(reject: reject)
        await sender.handle(accept: accept("t1"))
        for _ in 0..<200 { await Task.yield() }

        #expect(chunks(await session.sent.map(\.payload)).isEmpty)
        #expect(await sender.state == .rejected(.declined))
    }

    @Test
    func macosSender_fileCancelReceived_noFurtherFramesAndStateCancelled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = FakeTandemSession()
        let sender = makeSender(source: try fixture.file(bytes: Data(count: 1000)), session: session)

        await sender.start()
        var cancel = Tandem_V1_FileCancel()
        cancel.id = "t1"
        cancel.reason = .userCancelled
        await sender.handle(cancel: cancel)
        await sender.handle(accept: accept("t1"))
        for _ in 0..<200 { await Task.yield() }

        #expect(await session.sent.count == 1)
        #expect(await sender.state == .cancelled(.userCancelled))
        #expect(await sender.nextFrame() == nil)
    }

    @Test
    func macosSender_sourceReadFailsMidTransfer_sendsFileCancelIoError() async throws {
        let session = FakeTandemSession()
        let sender = makeSender(source: FlakySource(totalBytes: 3 * chunkSize), session: session)

        await sender.start()
        await sender.handle(accept: accept("t1"))
        await settle { await session.sent.contains { if case .fileCancel = $0.payload { true } else { false } } }

        let payloads = await session.sent.map(\.payload)
        guard case .fileCancel(let cancel)? = payloads.last else {
            Issue.record("expected FileCancel last")
            return
        }
        #expect(cancel.reason == .ioError)
        #expect(chunks(payloads).count == 1)
        #expect(payloads.contains { isComplete($0) } == false)
        #expect(await sender.state == .cancelled(.ioError))
    }
}
