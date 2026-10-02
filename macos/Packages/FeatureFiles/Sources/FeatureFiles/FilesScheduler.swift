import Foundation
import TandemProtocol

/// One logical FILES stream (a transfer, or a queued page/thumb response) feeding the scheduler.
public protocol FilesFrameStream: Sendable {
    /// The next payload to send on FILES, or `nil` once this stream has nothing more to send.
    func nextFrame() async -> Tandem_V1_Envelope.OneOf_Payload?
}

private struct SingleFrameStream: FilesFrameStream {
    let payload: Tandem_V1_Envelope.OneOf_Payload

    func nextFrame() async -> Tandem_V1_Envelope.OneOf_Payload? {
        payload
    }
}

/// Round-robins outgoing FILES frames per logical stream, one frame per turn, so a queued
/// `ThumbResult`/`PhotoPageResult` waits behind at most one `FileChunk`
/// (docs/protocol/SPEC.md #files-channel "Sender interleaving"). Credit gating happens inside
/// `TandemSession.send`, which suspends while FILES credits are exhausted.
public actor FilesScheduler {
    private let session: any TandemSession
    private var queue: [any FilesFrameStream] = []
    private var isDraining = false

    public init(session: any TandemSession) {
        self.session = session
    }

    public func enqueue(stream: any FilesFrameStream) {
        queue.append(stream)
        startDrainingIfIdle()
    }

    public func enqueue(response payload: Tandem_V1_Envelope.OneOf_Payload) {
        enqueue(stream: SingleFrameStream(payload: payload))
    }

    private func startDrainingIfIdle() {
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let stream = queue.removeFirst()
            guard let payload = await stream.nextFrame() else { continue }
            guard (try? await session.send(.files, payload: payload)) != nil else { continue }
            if !(stream is SingleFrameStream) {
                queue.append(stream)
            }
        }
        isDraining = false
    }
}
