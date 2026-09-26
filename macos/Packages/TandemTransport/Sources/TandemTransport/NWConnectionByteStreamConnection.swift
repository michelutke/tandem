import Foundation
import Network

/// Adapts a real, already-admitted `NWConnection` to ``ByteStreamConnection`` (E00-25) -- the
/// "Network.framework adapter" that type's own kdoc says backs production traffic (E12-12).
/// `send`/`receive` wrap `NWConnection`'s completion-handler API as an async throwing call and
/// stream; ``state`` is fed entirely by ``reportReady()``/``reportClosed()``/``reportFailed(_:)``/
/// ``reportCancelled()`` rather than installing a second `stateUpdateHandler` on `connection` --
/// `NWConnection` allows only one, and `ListenerFactory`'s own handler (E12-01/E12-18 admission
/// bookkeeping) already owns it, so it calls these after every transition instead.
final class NWConnectionByteStreamConnection: ByteStreamConnection, @unchecked Sendable {
    private let connection: NWConnection
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    let state: AsyncStream<ConnectionState>

    private static let maximumReceiveLength = 64 * 1024

    init(connection: NWConnection) {
        self.connection = connection
        (state, stateContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func reportReady() {
        stateContinuation.yield(.ready)
    }

    func reportClosed() {
        stateContinuation.yield(.closed)
        stateContinuation.finish()
    }

    func reportFailed(_ reason: String) {
        stateContinuation.yield(.failed(ConnectionFailure(reason)))
        stateContinuation.finish()
    }

    func reportCancelled() {
        stateContinuation.yield(.cancelled)
        stateContinuation.finish()
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            self.scheduleReceive(into: continuation)
        }
    }

    /// Re-arms `NWConnection.receive` after every delivered chunk -- a single `receive` call only
    /// ever delivers once, never a continuous stream on its own.
    private func scheduleReceive(into continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumReceiveLength) { [weak self] data, _, isComplete, error in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            if let data, !data.isEmpty {
                continuation.yield(data)
            }
            if isComplete {
                continuation.finish()
                return
            }
            self?.scheduleReceive(into: continuation)
        }
    }

    func cancel() {
        connection.cancel()
    }
}
