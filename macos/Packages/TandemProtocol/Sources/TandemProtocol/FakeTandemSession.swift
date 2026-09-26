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
actor FakeTandemSession: TandemSession {
    /// One recorded ``send(_:payload:)`` call, in call order.
    struct SentFrame: Sendable, Equatable {
        let channel: Tandem_V1_Channel
        let payload: Tandem_V1_Envelope.OneOf_Payload
    }

    private(set) var sent: [SentFrame] = []

    private var streams: [Tandem_V1_Channel: AsyncStream<InboundFrame>] = [:]
    private var continuations: [Tandem_V1_Channel: AsyncStream<InboundFrame>.Continuation] = [:]

    nonisolated let state: AsyncStream<ConnectionStateMachine.ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionStateMachine.ConnectionState>.Continuation

    init() {
        let (state, continuation) = AsyncStream<ConnectionStateMachine.ConnectionState>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.state = state
        stateContinuation = continuation
    }

    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        sent.append(SentFrame(channel: channel, payload: payload))
    }

    /// Returns an equivalent stream on every call for a given `channel`, matching
    /// ``ChannelMultiplexer/inbound(_:)``, so a frame ``inject(_:)``ed before this is ever called
    /// for that channel is not dropped.
    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        InboundFrameStream(base: streamFor(channel), onConsumed: {})
    }

    /// Injects `frame` as if it had arrived on its own `channel`, observed by any caller holding
    /// (or later requesting) ``receive(_:)`` for that channel.
    func inject(_ frame: InboundFrame) {
        _ = streamFor(frame.channel)
        continuations[frame.channel]?.yield(frame)
    }

    /// Publishes `newState` on ``state``.
    func emit(_ newState: ConnectionStateMachine.ConnectionState) {
        stateContinuation.yield(newState)
    }

    func close() async {
        for continuation in continuations.values {
            continuation.finish()
        }
        stateContinuation.yield(.disconnected(reason: "closed locally"))
        stateContinuation.finish()
    }

    private func streamFor(_ channel: Tandem_V1_Channel) -> AsyncStream<InboundFrame> {
        if let stream = streams[channel] {
            return stream
        }
        let (stream, continuation) = AsyncStream<InboundFrame>.makeStream(bufferingPolicy: .unbounded)
        streams[channel] = stream
        continuations[channel] = continuation
        return stream
    }
}
#endif
