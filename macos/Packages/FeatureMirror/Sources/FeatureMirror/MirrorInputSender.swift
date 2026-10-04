import CoreGraphics
import Foundation
import TandemProtocol

/// Sends mapped input on the control session's `INPUT` channel, only while the mirror session it was
/// created for is active (invariant 8): ends on `stop()` and when the control session leaves Ready.
@MainActor
public final class MirrorInputSender {
    private let session: any TandemSession
    private let model: MirrorWindowModel
    private var mapper: MirrorInputMapper
    public private(set) var isActive = true
    private let outbound: AsyncStream<Tandem_V1_InputEvent>.Continuation
    private var sendTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

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
        let states = session.state
        stateTask = Task { [weak self] in
            for await state in states where Self.isTerminal(state) {
                break
            }
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    deinit {
        outbound.finish()
        stateTask?.cancel()
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
        stateTask?.cancel()
    }

    /// Suspends until every event handled so far has been handed to the session.
    func drain() async {
        outbound.finish()
        await sendTask?.value
        stateTask?.cancel()
    }

    private nonisolated static func isTerminal(_ state: ConnectionStateMachine.ConnectionState) -> Bool {
        switch state {
        case .dead, .failed: true
        case .disconnected(let reason): reason != nil
        case .accepted, .tlsHandshaking, .helloExchange, .ready: false
        }
    }
}
