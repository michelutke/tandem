import Foundation

/// The production ``TandemSession`` implementation: composes a ``ChannelMultiplexer`` (E11-08)
/// with the ``ConnectionStateMachine`` (E12-09) tracking the same connection. Named for what
/// backs it in production -- a `ByteStreamConnection` (E00-25), `NWConnection` for real traffic
/// -- though this type itself never references that protocol: `TandemProtocol` may not depend on
/// `TandemTransport` (PRD module rules: transport depends on protocol, never the reverse), so a
/// caller adapts a real connection's bytes to ``FrameSource``/``ChannelMultiplexer/OutboundSink``
/// before constructing the ``ChannelMultiplexer`` this type wraps, exactly as
/// `InMemoryFrameSource` (`TandemProtocolTests`) adapts `InMemoryConnectionPair` in tests. Swift
/// counterpart to the Android `ByteStream`-backed session (E12-11).
///
/// Neither the injected multiplexer nor state machine is started by `init` -- mirroring
/// ``ChannelMultiplexer/start()`` and ``VersionHandshake/run()``, both already called explicitly
/// by whoever assembles a connection's pipeline -- so a caller controls exactly when reading and
/// the handshake deadline begin.
public actor ByteStreamSession: TandemSession {
    private let multiplexer: ChannelMultiplexer
    private let stateMachine: ConnectionStateMachine
    private var fanOuts: [Tandem_V1_Channel: Broadcast<InboundFrame>] = [:]

    public nonisolated var state: AsyncStream<ConnectionStateMachine.ConnectionState> {
        stateMachine.states
    }

    public init(multiplexer: ChannelMultiplexer, stateMachine: ConnectionStateMachine) {
        self.multiplexer = multiplexer
        self.stateMachine = stateMachine
    }

    public func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        try await multiplexer.send(channel, payload: payload)
    }

    /// The one dispatch point per channel (E22-12, mirroring the Android `ChannelDispatcher`): a
    /// single reader pulls the channel's frames and fans every frame out to each caller's own
    /// stream, so any number of features may read the same channel without splitting its frames.
    /// The slowest subscriber paces the channel: the reader pulls at most ``fanOutWindow`` frames
    /// ahead of any subscriber, and a frame counts as consumed for peer credit replenishment
    /// (``ChannelMultiplexer/frameConsumed(_:)``) only when pulled, so a subscriber that stops
    /// consuming stops the peer's credit instead of growing memory. The reader starts at the first
    /// call for a channel and holds frames for that first caller; a later caller sees only frames
    /// arriving after it subscribed.
    public func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream {
        if let existing = fanOuts[channel] {
            return Self.subscription(to: existing)
        }
        let fanOut = Broadcast<InboundFrame>()
        fanOuts[channel] = fanOut
        let subscription = Self.subscription(to: fanOut)
        let source = await multiplexer.rawInbound(channel)
        let multiplexer = multiplexer
        Task {
            var iterator = source.makeAsyncIterator()
            while true {
                await fanOut.awaitCapacity(limit: Self.fanOutWindow)
                guard let frame = await iterator.next() else { break }
                fanOut.publish(frame)
                await multiplexer.frameConsumed(channel)
            }
            fanOut.finish()
        }
        return subscription
    }

    static let fanOutWindow = 8

    private static func subscription(to fanOut: Broadcast<InboundFrame>) -> InboundFrameStream {
        let (stream, consumed) = fanOut.subscribeReportingConsumption()
        return InboundFrameStream(base: stream, onConsumed: consumed)
    }

    /// Moves ``ConnectionStateMachine/state`` to `disconnected` -- legal once the connection has
    /// reached `Ready` (an earlier state leaves ``ConnectionStateMachine/handle(_:)`` a no-op,
    /// matching that machine's own illegal-event contract) -- and stops the multiplexer
    /// (``ChannelMultiplexer/stop()``), finishing every channel's ``receive(_:)`` stream
    /// even if a subscriber stalled. Safe to call more than once: both `stateMachine.handle(_:)` and
    /// `multiplexer.stop()` are no-ops
    /// once already stopped.
    public func close() async {
        await stateMachine.handle(.socketClosed(reason: "closed locally"))
        await multiplexer.stop()
        fanOuts.values.forEach { $0.finish() }
    }
}
