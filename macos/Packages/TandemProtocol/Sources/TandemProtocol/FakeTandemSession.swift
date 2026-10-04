#if DEBUG
// Test double only; compiled out of release builds (E00-30 release scan).
import Foundation

/// Test double for ``TandemSession``: records every ``send(_:payload:)`` call in order and lets a
/// test inject frames a caller observes via ``receive(_:)`` and states a caller observes via
/// ``state``. Swift counterpart to the Android `FakeTandemSession` (E12-11), also the seam the
/// DEBUG-only E00-26 scenario seeding uses.
///
/// This issue's own description places `FakeTandemSession` in `TandemTestSupport`, but
/// `TandemSession`'s `channel`/`payload` parameter types are internal to `TandemProtocol` (the
/// generated protobuf code is not built `Visibility=Public` -- see ``FrameSource``'s own doc
/// comment), and `TandemProtocol`'s own `Package.swift` already depends on `TandemTestSupport`
/// for its test target, so a `TandemTestSupport -> TandemProtocol` dependency the other way would
/// be a package-graph cycle. This stays alongside ``ByteStreamSession`` in `TandemProtocol`
/// instead, exercised via `@testable import TandemProtocol` the same way every other fake in this
/// package's own test target already is (``InMemoryFrameSource``, `TandemProtocolTests`).
public actor FakeTandemSession: TandemSession {
    /// One recorded ``send(_:payload:)`` call, in call order.
    public struct SentFrame: Sendable, Equatable {
        public let channel: Tandem_V1_Channel
        public let payload: Tandem_V1_Envelope.OneOf_Payload
    }

    public private(set) var sent: [SentFrame] = []

    private var fanOuts: [Tandem_V1_Channel: Broadcast<InboundFrame>] = [:]
    private var isSetupSealed = false
    private var isClosed = false

    public nonisolated let state: AsyncStream<ConnectionStateMachine.ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionStateMachine.ConnectionState>.Continuation

    public init() {
        let (state, continuation) = AsyncStream<ConnectionStateMachine.ConnectionState>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.state = state
        stateContinuation = continuation
    }

    public func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        sent.append(SentFrame(channel: channel, payload: payload))
    }

    /// Returns a new subscription on every call for a given `channel`, matching
    /// ``ByteStreamSession/receive(_:)``: the first caller also gets every frame
    /// ``inject(_:)``ed before it subscribed; later callers see only frames injected afterwards.
    public func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        InboundFrameStream(base: fanOut(for: channel).subscribe(), onConsumed: {})
    }

    /// Injects `frame` as if it had arrived on its own `channel`, observed by any caller holding
    /// (or later requesting) ``receive(_:)`` for that channel.
    func inject(_ frame: InboundFrame) {
        fanOut(for: frame.channel).publish(frame)
    }

    /// Publishes `newState` on ``state``.
    func emit(_ newState: ConnectionStateMachine.ConnectionState) {
        stateContinuation.yield(newState)
    }

    public func sealSetup() {
        isSetupSealed = true
        fanOuts[.control]?.seal()
    }

    public func close() async {
        isClosed = true
        fanOuts.values.forEach { $0.finish() }
        stateContinuation.yield(.disconnected(reason: "closed locally"))
        stateContinuation.finish()
    }

    private func fanOut(for channel: Tandem_V1_Channel) -> Broadcast<InboundFrame> {
        if let fanOut = fanOuts[channel] {
            return fanOut
        }
        let fanOut = Broadcast<InboundFrame>(replayUntilSealed: channel == .control && !isSetupSealed)
        if isClosed { fanOut.finish() }
        fanOuts[channel] = fanOut
        return fanOut
    }
}
#endif
