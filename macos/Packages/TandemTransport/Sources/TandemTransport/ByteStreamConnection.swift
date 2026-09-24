import Foundation

/// Lifecycle of a ``ByteStreamConnection``, mirroring the subset of `NWConnection.State` the
/// transport reacts to.
public enum ConnectionState: Sendable, Equatable {
    case ready
    /// The peer finished sending in an orderly way (EOF / TLS close_notify).
    case closed
    /// This end was cancelled locally.
    case cancelled
    /// The connection broke (peer vanished, reset, transport error).
    case failed(ConnectionFailure)
}

public struct ConnectionFailure: Error, Sendable, Equatable {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// The byte-stream seam every protocol layer above the socket is written against (E00-25).
/// The Network.framework adapter implements it in E12; tests use `InMemoryConnectionPair`.
public protocol ByteStreamConnection: Sendable {
    /// Sends `data`, suspending while the peer applies backpressure.
    func send(_ data: Data) async throws
    /// Bytes from the peer in arrival order. Finishes on orderly close, throws on failure.
    func receive() -> AsyncThrowingStream<Data, Error>
    var state: AsyncStream<ConnectionState> { get }
    /// Abruptly tears the connection down; the peer observes `.failed`.
    func cancel()
}
