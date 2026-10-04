import Foundation
import Synchronization

/// Wraps a ``ByteStreamConnection`` whose first bytes were already read ahead (to classify the
/// connection, E60-03): ``receive()`` replays `prefix` before continuing with the base stream.
/// Pull-driven like the base stream, so a slow consumer never makes it buffer more.
final class PrefixedByteStreamConnection: ByteStreamConnection, Sendable {
    private let base: any ByteStreamConnection
    private let pendingPrefix: Mutex<Data?>

    init(_ base: any ByteStreamConnection, prefix: Data) {
        self.base = base
        pendingPrefix = Mutex(prefix.isEmpty ? nil : prefix)
    }

    var state: AsyncStream<ConnectionState> { base.state }

    func send(_ data: Data) async throws {
        try await base.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        let pump = Pump(prefix: pendingPrefix.withLock { $0.take() }, base: base.receive())
        return AsyncThrowingStream(unfolding: { try await pump.next() })
    }

    func cancel() {
        base.cancel()
    }

    private final class Pump: @unchecked Sendable {
        private var prefix: Data?
        private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator

        init(prefix: Data?, base: AsyncThrowingStream<Data, Error>) {
            self.prefix = prefix
            iterator = base.makeAsyncIterator()
        }

        func next() async throws -> Data? {
            if let prefix {
                self.prefix = nil
                return prefix
            }
            return try await iterator.next()
        }
    }
}
