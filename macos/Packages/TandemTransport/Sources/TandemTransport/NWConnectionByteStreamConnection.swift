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

    /// Pull-driven (`AsyncThrowingStream(unfolding:)`): `NWConnection.receive` is only re-armed
    /// once a consumer actually asks for the next element (`ChannelMultiplexer`'s reader loop,
    /// one `read(exactly:)` at a time), rather than eagerly buffering everything the peer sends
    /// into an unbounded stream regardless of whether anything is reading it -- an authenticated
    /// but otherwise idle/slow peer can otherwise grow this process's memory without bound
    /// (docs/protocol/SPEC.md §10, "rejected before any allocation").
    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(unfolding: { [weak self] in
            guard let self else { return nil }
            return try await self.receiveOnce()
        })
    }

    private func receiveOnce() async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: Self.maximumReceiveLength
            ) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    // Either a clean end of stream (`isComplete`), or -- defensively, since
                    // `NWConnection.receive`'s contract always delivers data, completion, or an
                    // error -- an empty, non-terminal callback treated the same way: no more
                    // elements from this call, so the unfolding sequence ends rather than looping
                    // here (a genuinely non-terminal empty callback would be a `Network` bug, not
                    // one this adapter should spin retrying).
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func cancel() {
        connection.cancel()
    }
}
