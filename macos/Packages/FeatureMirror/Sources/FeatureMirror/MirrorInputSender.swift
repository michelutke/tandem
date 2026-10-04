import CoreGraphics
import Foundation
import TandemProtocol

/// Sends mapped input on the control session's `INPUT` channel, only while the mirror session it was
/// created for is active (invariant 8): ends on `stop()`, which the owner calls when the media
/// stream or its control session ends.
@MainActor
public final class MirrorInputSender {
    private let session: any TandemSession
    private let model: MirrorWindowModel
    private var mapper: MirrorInputMapper
    public private(set) var isActive = true
    private let outbound: AsyncStream<Tandem_V1_InputEvent>.Continuation
    private var sendTask: Task<Void, Never>?

    public init?(session: any TandemSession, sessionId: Data, model: MirrorWindowModel) {
        guard let mapper = MirrorInputMapper(sessionId: sessionId) else { return nil }
        self.session = session
        self.model = model
        self.mapper = mapper
        let (events, continuation) = AsyncStream<Tandem_V1_InputEvent>.makeStream()
        outbound = continuation
        sendTask = Task {
            for await event in events {
                try? await session.send(.input, payload: .inputEvent(event))
            }
        }
    }

    deinit {
        outbound.finish()
    }

    public func setWindowKey(_ isKey: Bool) {
        mapper.isWindowKey = isKey
    }

    public func handle(_ event: MirrorInputEvent) {
        guard isActive else { return }
        mapper.streamSize = model.streamSize
        mapper.windowSize = model.windowSize
        mapper.map(event).forEach { outbound.yield($0) }
    }

    public func stop() {
        isActive = false
        mapper.isWindowKey = false
    }

    /// Suspends until every event handled so far has been handed to the session.
    func drain() async {
        outbound.finish()
        await sendTask?.value
    }
}
