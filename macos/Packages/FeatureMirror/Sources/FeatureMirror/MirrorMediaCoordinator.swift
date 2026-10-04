import CoreGraphics
import Foundation
import TandemProtocol
import TandemTransport

/// The AppKit window the mirror stream is shown in; implemented by the app target.
@MainActor
public protocol MirrorWindowPresenting: AnyObject, Sendable {
    /// Opens the window and returns the sink decoded frames are enqueued on. `inputSender` is the
    /// window's input path, `nil` when none is available. `onUserClose` is called when the user closes
    /// the window.
    func present(
        model: MirrorWindowModel,
        inputSender: MirrorInputSender?,
        onUserClose: @escaping @MainActor () -> Void
    ) -> any SampleBufferSink
    func dismiss()
}

/// Feeds a bound media connection into a mirror window: `MediaMessage` framing, fragment reassembly,
/// ``DecodePipeline``, ``MirrorWindowPresenting``. At most one stream is live; it ends, closing the
/// connection and the window, when its session ends, the user closes the window or the peer
/// violates the media framing.
@MainActor
public final class MirrorMediaCoordinator {
    private struct Active {
        let id: MediaSessionID
        let stream: MirrorMediaStream
    }

    private nonisolated let presenter: any MirrorWindowPresenting
    private nonisolated let inputSession: @MainActor (MediaSessionID) -> (any TandemSession)?
    private var active: Active?

    /// - Parameter inputSession: The control session of the given media session; mapped window input is sent on it.
    public nonisolated init(
        presenter: any MirrorWindowPresenting,
        inputSession: @escaping @MainActor (MediaSessionID) -> (any TandemSession)? = { _ in nil }
    ) {
        self.presenter = presenter
        self.inputSession = inputSession
    }

    /// `mirrorSessionId` is the 16-byte id from the bound `MediaHello`; input is sent with it only
    /// while this stream is live.
    public func mediaBound(
        _ connection: any ByteStreamConnection,
        sessionID: MediaSessionID,
        mirrorSessionId: Data
    ) {
        active?.stream.stop()
        let stream = MirrorMediaStream(
            connection: connection,
            presenter: presenter,
            mirrorSessionId: mirrorSessionId,
            inputSession: inputSession(sessionID)
        )
        active = Active(id: sessionID, stream: stream)
        stream.start { [weak self, weak stream] in
            guard let self, let stream, self.active?.stream === stream else { return }
            self.active = nil
        }
    }

    public func sessionEnded(_ id: MediaSessionID) {
        guard active?.id == id else { return }
        active?.stream.stop()
    }
}

@MainActor
private final class MirrorMediaStream {
    private let connection: any ByteStreamConnection
    private let presenter: any MirrorWindowPresenting
    private let mirrorSessionId: Data
    private let inputSession: (any TandemSession)?
    private var inputSender: MirrorInputSender?
    private var parser = MediaMessageParser()
    private var reassembler = FragmentReassembler()
    private var model: MirrorWindowModel?
    private var pipeline: DecodePipeline?
    private var task: Task<Void, Never>?
    private var isWindowOpen = false

    init(
        connection: any ByteStreamConnection,
        presenter: any MirrorWindowPresenting,
        mirrorSessionId: Data,
        inputSession: (any TandemSession)?
    ) {
        self.connection = connection
        self.presenter = presenter
        self.mirrorSessionId = mirrorSessionId
        self.inputSession = inputSession
    }

    func start(onFinished: @escaping @MainActor () -> Void) {
        task = Task { [self] in
            await run()
            onFinished()
        }
    }

    func stop() {
        task?.cancel()
        finish()
    }

    private func run() async {
        do {
            for try await chunk in connection.receive() {
                parser.append(chunk)
                while let message = try parser.nextMessage() {
                    try handle(message)
                }
            }
        } catch {}
        finish()
    }

    private func finish() {
        connection.cancel()
        pipeline = nil
        inputSender?.stop()
        inputSender = nil
        guard isWindowOpen else { return }
        isWindowOpen = false
        presenter.dismiss()
    }

    private func handle(_ message: Tandem_V1_MediaMessage) throws(MediaFrameError) {
        switch message.payload {
        case .mediaFormat(let format)?: try formatChanged(format)
        case .mediaFrame(let frame)?: try frameReceived(frame)
        case .rotationChanged(let rotation)?: model?.rotationChanged(rotation.orientation)
        case .keyframeRequest?, nil: break
        }
    }

    private func formatChanged(_ format: Tandem_V1_MediaFormat) throws(MediaFrameError) {
        let codec: VideoCodec
        switch format.codec {
        case .h264: codec = .h264
        case .hevc: codec = .hevc
        case .unspecified, .UNRECOGNIZED: throw .malformedFrame
        }
        reassembler = FragmentReassembler()
        if let model, let pipeline {
            model.mediaFormatChanged(width: Int(format.width), height: Int(format.height))
            pipeline.reset(codec: codec)
            return
        }
        let size = CGSize(width: Int(format.width), height: Int(format.height))
        let model = MirrorWindowModel(streamSize: size, windowSize: size)
        inputSender = inputSession.flatMap { MirrorInputSender(session: $0, sessionId: mirrorSessionId, model: model) }
        let sink = presenter.present(
            model: model, inputSender: inputSender, onUserClose: { [weak self] in self?.stop() }
        )
        isWindowOpen = true
        self.model = model
        pipeline = DecodePipeline(codec: codec, sink: sink, keyframeRequests: KeyframeSender(connection))
    }

    private func frameReceived(_ frame: Tandem_V1_MediaFrame) throws(MediaFrameError) {
        guard let pipeline else { throw .malformedFrame }
        guard let accessUnit = try reassembler.accept(
            pts: frame.pts, fragmentIndex: frame.fragmentIndex, fragmentCount: frame.fragmentCount, data: frame.data
        ) else { return }
        pipeline.submit(accessUnit: accessUnit, pts: frame.pts, isKeyframe: frame.flags & 0x1 != 0)
    }
}

private struct KeyframeSender: KeyframeRequestSink {
    let connection: any ByteStreamConnection

    init(_ connection: any ByteStreamConnection) {
        self.connection = connection
    }

    func requestKeyframe() {
        var message = Tandem_V1_MediaMessage()
        message.keyframeRequest = Tandem_V1_KeyframeRequest()
        guard let frame = MediaMessageParser.encode(message) else { return }
        let connection = connection
        Task { try? await connection.send(frame) }
    }
}
