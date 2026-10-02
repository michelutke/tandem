import Foundation
import Testing
import TandemTestSupport
@testable import FeatureFiles
@testable import TandemProtocol

private let chunkSize = 262_144

private actor GatedSession: TandemSession {
    private let inner = FakeTandemSession()
    private var gateOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var blockedSends = 0

    nonisolated var state: AsyncStream<ConnectionStateMachine.ConnectionState> { inner.state }

    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        if !gateOpen {
            blockedSends += 1
            await withCheckedContinuation { waiters.append($0) }
        }
        try await inner.send(channel, payload: payload)
    }

    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        await inner.receive(channel)
    }

    func close() async { await inner.close() }

    func openGate() {
        gateOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func sentPayloads() async -> [Tandem_V1_Envelope.OneOf_Payload] {
        await inner.sent.map(\.payload)
    }
}

private final class DataFrameSource: FrameSource, @unchecked Sendable {
    private var data: Data

    init(_ data: Data) { self.data = data }

    func read(exactly count: Int) async throws -> Data {
        let result = data.prefix(count)
        data = Data(data.dropFirst(count))
        return Data(result)
    }
}

private final class PairFrameSource: FrameSource, @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private var buffer = Data()

    init(_ end: InMemoryConnectionPair.End) { iterator = end.receive().makeAsyncIterator() }

    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            guard let next = try await iterator.next() else {
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(next)
        }
        defer { buffer.removeFirst(count) }
        return Data(buffer.prefix(count))
    }
}

private func writeFile(chunks: Int) throws -> (URL, LocalFileChunkSource) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(count: chunks * chunkSize).write(to: url)
    return (url, LocalFileChunkSource(url: url))
}

private func settle(until condition: () async -> Bool) async {
    for _ in 0..<5000 {
        if await condition() { return }
        await Task.yield()
    }
}

private func accept() -> Tandem_V1_FileAccept {
    var message = Tandem_V1_FileAccept()
    message.id = "t1"
    return message
}

private func wireChunkCount(_ pair: InMemoryConnectionPair) async throws -> Int {
    let source = DataFrameSource(await pair.captured(.aToB))
    var count = 0
    while case .frame(let envelope)? = try await FrameDecoder.decode(from: source) {
        if case .fileChunk? = envelope.payload { count += 1 }
    }
    return count
}

@Suite("FilesScheduler")
struct FilesSchedulerTests {
    @Test
    func macosFilesScheduler_transferInFlight_thumbResultSentWithinOneChunk() async throws {
        let (url, source) = try writeFile(chunks: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = GatedSession()
        let scheduler = FilesScheduler(session: session)
        let sender = FileSender(
            id: "t1", name: "f.bin", mime: "application/octet-stream",
            source: source, session: FakeTandemSession(), scheduler: scheduler
        )

        await sender.start()
        await sender.handle(accept: accept())
        await settle { await session.blockedSends == 1 }

        var thumb = Tandem_V1_ThumbResult()
        thumb.id = "p1"
        await scheduler.enqueue(response: .thumbResult(thumb))
        await session.openGate()
        await settle { await session.sentPayloads().count == 7 }

        let payloads = await session.sentPayloads()
        let thumbIndex = payloads.firstIndex { if case .thumbResult = $0 { true } else { false } }
        #expect(thumbIndex != nil)
        #expect((thumbIndex ?? payloads.count) <= 1)
    }

    @Test
    func macosSender_zeroFilesCredits_noChunkUntilGrant() async throws {
        let (url, source) = try writeFile(chunks: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let pair = InMemoryConnectionPair(bufferCapacity: 16 << 20)
        let multiplexer = ChannelMultiplexer(source: PairFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()
        let session = ByteStreamSession(
            multiplexer: multiplexer, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
        )
        let sender = FileSender(
            id: "t1", name: "f.bin", mime: "application/octet-stream",
            source: source, session: session, scheduler: FilesScheduler(session: session)
        )

        await sender.start()
        for _ in 0..<(CreditCaps.capFor(.files) - 1) {
            try await session.send(.files, payload: .heartbeat(Tandem_V1_Heartbeat()))
        }
        await sender.handle(accept: accept())
        for _ in 0..<200 { await Task.yield() }
        #expect(try await wireChunkCount(pair) == 0)

        var grant = Tandem_V1_CreditGrant()
        grant.channel = .files
        grant.amount = 2
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.payload = .creditGrant(grant)
        try await pair.endB.send(try FrameEncoder.encode(envelope))

        await settle { (try? await wireChunkCount(pair)) == 2 }
        for _ in 0..<200 { await Task.yield() }
        #expect(try await wireChunkCount(pair) == 2)
    }
}
