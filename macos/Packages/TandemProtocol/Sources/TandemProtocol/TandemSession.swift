import Foundation

/// Transport session abstraction exposing per-channel frame streams over an already-accepted
/// connection (E12-09 connection state, E11-08 flow control). Swift counterpart to the Android
/// `TandemSession` (E12-11): `send`/`receive` per channel, a `state` stream, and `close()`. Kept
/// transport-agnostic -- no `Network` framework type appears in any requirement below, and
/// `TandemProtocol` may not depend on `TandemTransport` (PRD module rules: transport depends on
/// protocol, never the reverse) -- so a future USB transport (F-10.3) can implement it without
/// touching feature code. ``ByteStreamSession`` is the production implementation, composing a
/// ``ChannelMultiplexer`` (E11-08) with a ``ConnectionStateMachine`` (E12-09) built from bytes
/// adapted from a real `ByteStreamConnection` (E00-25); `InMemoryConnectionPair` stands in for
/// that adapter in tests exactly as it already does for ``ChannelMultiplexer`` itself.
///
/// Cycle 8 (D-67; supersedes the original Cycle 4 `channelBinding` property): exposes no
/// `channelBinding` property and no exporter API of any kind -- channel binding is not a
/// transport concern (docs/protocol/SPEC.md #channel-binding). `cb` is the in-band
/// `PairChallenge`/`RotationChallenge` value, generated, sent and held entirely by the pairing
/// (E14) and key-rotation (E70) layers, which read it from an ordinary received frame like any
/// other CONTROL payload, never from this protocol.
public protocol TandemSession: Sendable {
    /// Sends `payload` on `channel` (``ChannelMultiplexer/send(_:payload:)``).
    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws

    /// The frames arriving on `channel`, in arrival order (``ChannelMultiplexer/inbound(_:)``).
    /// Finishes once this session ``close()``s.
    func receive(_ channel: Tandem_V1_Channel) async -> InboundFrameStream

    /// This session's own connection-state stream (``ConnectionStateMachine/states``).
    var state: AsyncStream<ConnectionStateMachine.ConnectionState> { get }

    /// Tears this session down: moves ``state`` to `disconnected`, finishing it, and finishes
    /// every ``receive(_:)`` stream. Safe to call more than once.
    func close() async
}
