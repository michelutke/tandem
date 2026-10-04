import CoreGraphics
import Foundation
import TandemProtocol
import TandemTransport

/// The AppKit window the mirror stream is shown in; implemented by the app target.
@MainActor
public protocol MirrorWindowPresenting: AnyObject, Sendable {
    /// Opens the window and returns the sink decoded frames are enqueued on. `onUserClose` is called
    /// when the user closes the window.
    func present(model: MirrorWindowModel, onUserClose: @escaping @MainActor () -> Void) -> any SampleBufferSink
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
    private var active: Active?

    public nonisolated init(presenter: any MirrorWindowPresenting) {
        self.presenter = presenter
    }

    public func mediaBound(_ connection: any ByteStreamConnection, sessionID: MediaSessionID) {
        active?.stream.stop()
        let stream = MirrorMediaStream(connection: connection, presenter: presenter)
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
    private var parser = MediaMessageParser()
    private var reassembler = FragmentReassembler()
    private var model: MirrorWindowModel?
    private var pipeline: DecodePipeline?
    private var task: Task<Void, Never>?
    private var isWindowOpen = false

    init(connection: any ByteStreamConnection, presenter: any MirrorWindowPresenting) {
        self.connection = connection
        self.presenter = presenter
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
        let sink = presenter.present(model: model, onUserClose: { [weak self] in self?.stop() })
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
