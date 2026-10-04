import CoreMedia
import Foundation
import Synchronization
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemProtocol
import TandemTransport
@testable import FeatureMirror

private final class SinkRecorder: SampleBufferSink, @unchecked Sendable {
    private let count = Mutex(0)
    var enqueued: Int { count.withLock { $0 } }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        count.withLock { $0 += 1 }
    }
}

@MainActor
private final class RecordingPresenter: MirrorWindowPresenting {
    let sink = SinkRecorder()
    private(set) var presentedSizes: [CGSize] = []
    private(set) var inputSender: MirrorInputSender?
    private(set) var dismissCount = 0

    func present(
        model: MirrorWindowModel,
        inputSender: MirrorInputSender?,
        onUserClose: @escaping @MainActor () -> Void
    ) -> any SampleBufferSink {
        presentedSizes.append(model.streamSize)
        self.inputSender = inputSender
        return sink
    }

    func dismiss() {
        dismissCount += 1
    }
}

private final class ScriptedConnection: ByteStreamConnection, Sendable {
    private let cancelledFlag = Mutex(false)
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let stream: AsyncThrowingStream<Data, Error>

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    var cancelled: Bool { cancelledFlag.withLock { $0 } }

    func push(_ message: Tandem_V1_MediaMessage) throws {
        let body = try message.serializedData()
        var frame = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        continuation.yield(frame)
    }

    func send(_ data: Data) async throws {}
    func receive() -> AsyncThrowingStream<Data, Error> { stream }
    var state: AsyncStream<ConnectionState> { AsyncStream { $0.finish() } }

    func cancel() {
        cancelledFlag.withLock { $0 = true }
        continuation.finish()
    }
}

private let mirrorSessionId = Data(repeating: 0x5C, count: 16)

private func fingerprint(_ byte: UInt8) -> SpkiFingerprint {
    // swiftlint:disable:next force_try
    try! SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
}

private func h264AccessUnits() throws -> [(data: Data, isKeyframe: Bool)] {
    let url = try #require(
        Bundle.module.url(forResource: "h264-720p-30f", withExtension: "annexb", subdirectory: "Fixtures/media")
    )
    var units: [(Data, Bool)] = []
    var pending = Data()
    for nal in try AnnexBParser.parse(Data(contentsOf: url)) {
        pending.append(contentsOf: [0, 0, 0, 1])
        pending.append(nal.bytes)
        guard nal.h264Type == 1 || nal.h264Type == 5 else { continue }
        units.append((pending, nal.h264Type == 5))
        pending = Data()
    }
    return units
}

private func formatMessage() -> Tandem_V1_MediaMessage {
    var format = Tandem_V1_MediaFormat()
    format.codec = .h264
    format.width = 1280
    format.height = 720
    format.fps = 30
    var message = Tandem_V1_MediaMessage()
    message.mediaFormat = format
    return message
}

private func frameMessage(_ unit: (data: Data, isKeyframe: Bool), pts: UInt64) -> Tandem_V1_MediaMessage {
    var frame = Tandem_V1_MediaFrame()
    frame.pts = pts
    frame.flags = unit.isKeyframe ? 1 : 0
    frame.data = unit.data
    frame.fragmentIndex = 0
    frame.fragmentCount = 1
    var message = Tandem_V1_MediaMessage()
    message.mediaFrame = frame
    return message
}

private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<20_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

@Suite("Mirror composition")
@MainActor
struct MirrorCompositionTests {
    @Test
    func macMirrorComposition_mediaBound_windowShowsDecodedFrames() async throws {
        let presenter = RecordingPresenter()
        let coordinator = MirrorMediaCoordinator(presenter: presenter)
        let connection = ScriptedConnection()
        coordinator.mediaBound(
            connection, sessionID: MediaSessionID(rawValue: UUID()), mirrorSessionId: mirrorSessionId
        )

        let units = try h264AccessUnits()
        try connection.push(formatMessage())
        try connection.push(frameMessage(units[0], pts: 0))
        try connection.push(frameMessage(units[1], pts: 33_333))

        #expect(await eventually { presenter.sink.enqueued == 2 })
        #expect(presenter.presentedSizes == [CGSize(width: 1280, height: 720)])
        #expect(presenter.dismissCount == 0)
    }

    @Test
    func macMirrorComposition_controlSessionEnds_mediaAndWindowClosed() async throws {
        let presenter = RecordingPresenter()
        let coordinator = MirrorMediaCoordinator(presenter: presenter)
        let clock = ManualTestClock()
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        let issuer = MediaTicketIssuer(
            table: MediaTicketTable(clock: clock), source: SystemMediaTicketSource(), dateProvider: dates.provider)
        let registry = MediaSessionRegistry(issuer: issuer, onEnded: { id in
            Task { @MainActor in coordinator.sessionEnded(id) }
        })
        let session = FakeTandemSession()
        let id = MediaSessionID(rawValue: UUID())
        let peer = fingerprint(0xA1)
        await registry.register(states: session.state, id: id, peer: peer)
        let connection = ScriptedConnection()
        #expect(await registry.bind(connection, to: id, mirrorSessionId: mirrorSessionId, presentedBy: peer))
        coordinator.mediaBound(connection, sessionID: id, mirrorSessionId: mirrorSessionId)
        try connection.push(formatMessage())
        #expect(await eventually { presenter.presentedSizes.count == 1 })

        await session.emit(.dead)

        #expect(await eventually { connection.cancelled && presenter.dismissCount == 1 })
    }

    @Test
    func macMirrorComposition_malformedMediaFrame_closesConnectionAndWindow() async throws {
        let presenter = RecordingPresenter()
        let coordinator = MirrorMediaCoordinator(presenter: presenter)
        let connection = ScriptedConnection()
        coordinator.mediaBound(
            connection, sessionID: MediaSessionID(rawValue: UUID()), mirrorSessionId: mirrorSessionId
        )
        try connection.push(formatMessage())
        #expect(await eventually { presenter.presentedSizes.count == 1 })

        try connection.push(Tandem_V1_MediaMessage())

        #expect(await eventually { connection.cancelled && presenter.dismissCount == 1 })
    }

    @Test
    func macMirrorComposition_mediaBound_inputSenderUsesMediaHelloSessionId() async throws {
        let presenter = RecordingPresenter()
        let session = FakeTandemSession()
        let coordinator = MirrorMediaCoordinator(presenter: presenter, inputSession: { _ in session })
        let connection = ScriptedConnection()
        coordinator.mediaBound(
            connection, sessionID: MediaSessionID(rawValue: UUID()), mirrorSessionId: mirrorSessionId)
        try connection.push(formatMessage())
        #expect(await eventually { presenter.presentedSizes.count == 1 })
        let sender = try #require(presenter.inputSender)
        sender.setWindowKey(true)

        sender.handle(.pressed(point: CGPoint(x: 10, y: 10), time: 0))
        sender.handle(.released(point: CGPoint(x: 10, y: 10), time: 0.01))
        await sender.drain()

        let sent = await session.sent
        #expect(sent.count == 1)
        guard case .inputEvent(let event)? = sent.first?.payload else {
            Issue.record("expected inputEvent")
            return
        }
        #expect(event.sessionID == mirrorSessionId)
    }

    @Test
    func macMirrorComposition_twoPeers_mediaForFirst_senderUsesFirstPeersSession() async throws {
        let presenter = RecordingPresenter()
        let first = FakeTandemSession()
        let second = FakeTandemSession()
        let firstID = MediaSessionID(rawValue: UUID())
        let secondID = MediaSessionID(rawValue: UUID())
        let sessions = [firstID: first, secondID: second]
        let coordinator = MirrorMediaCoordinator(presenter: presenter, inputSession: { sessions[$0] })
        let connection = ScriptedConnection()
        coordinator.mediaBound(connection, sessionID: firstID, mirrorSessionId: mirrorSessionId)
        try connection.push(formatMessage())
        #expect(await eventually { presenter.presentedSizes.count == 1 })
        let sender = try #require(presenter.inputSender)
        sender.setWindowKey(true)

        sender.handle(.pressed(point: CGPoint(x: 10, y: 10), time: 0))
        sender.handle(.released(point: CGPoint(x: 10, y: 10), time: 0.01))
        await sender.drain()

        #expect(await first.sent.count == 1)
        #expect(await second.sent.isEmpty)
    }

    @Test
    func macMirrorComposition_controlSessionEnds_inputNotSentAndIdCleared() async throws {
        let presenter = RecordingPresenter()
        let session = FakeTandemSession()
        let coordinator = MirrorMediaCoordinator(presenter: presenter, inputSession: { _ in session })
        let clock = ManualTestClock()
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        let issuer = MediaTicketIssuer(
            table: MediaTicketTable(clock: clock), source: SystemMediaTicketSource(), dateProvider: dates.provider)
        let registry = MediaSessionRegistry(issuer: issuer, onEnded: { id in
            Task { @MainActor in coordinator.sessionEnded(id) }
        })
        let id = MediaSessionID(rawValue: UUID())
        let peer = fingerprint(0xA1)
        await registry.register(states: session.state, id: id, peer: peer)
        let connection = ScriptedConnection()
        #expect(await registry.bind(connection, to: id, mirrorSessionId: mirrorSessionId, presentedBy: peer))
        #expect(await registry.mirrorSessionId(for: id) == mirrorSessionId)
        coordinator.mediaBound(connection, sessionID: id, mirrorSessionId: mirrorSessionId)
        try connection.push(formatMessage())
        #expect(await eventually { presenter.presentedSizes.count == 1 })
        let sender = try #require(presenter.inputSender)

        await session.emit(.dead)
        #expect(await eventually { !sender.isActive })
        sender.handle(.scrolled(point: CGPoint(x: 10, y: 10), deltaX: 0, deltaY: 3, time: 0))
        await sender.drain()

        #expect(await session.sent.isEmpty)
        #expect(await registry.mirrorSessionId(for: id) == nil)
    }

    @Test
    func mediaSessionRegistry_reRegisterSameId_staleWatcherDoesNotEndNewEntry() async {
        let clock = ManualTestClock()
        let dates = FixedDateProvider(clock: clock, epoch: Date(timeIntervalSince1970: 1_000))
        let issuer = MediaTicketIssuer(
            table: MediaTicketTable(clock: clock), source: SystemMediaTicketSource(), dateProvider: dates.provider)
        let registry = MediaSessionRegistry(issuer: issuer)
        let first = FakeTandemSession()
        let second = FakeTandemSession()
        let id = MediaSessionID(rawValue: UUID())
        await registry.register(states: first.state, id: id, peer: fingerprint(1))
        await registry.register(states: second.state, id: id, peer: fingerprint(1))

        await first.emit(.dead)
        for _ in 0..<200 { await Task.yield() }

        #expect(await registry.requestTicket(for: id) != nil)
    }
}
