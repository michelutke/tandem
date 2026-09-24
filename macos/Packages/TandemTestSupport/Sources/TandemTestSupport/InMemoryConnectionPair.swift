import Foundation
import TandemTransport

/// Two connected in-memory ``ByteStreamConnection`` ends (E00-25), so codec, multiplexer,
/// flow-control, state-machine and transfer tests run without a socket. Each direction is a
/// bounded buffer: a sender suspends once `bufferCapacity` bytes are unread, which gives tests
/// real backpressure. Every byte that crosses a direction is also captured for assertions.
public final class InMemoryConnectionPair: Sendable {
    public enum Direction: Sendable {
        case aToB, bToA
    }

    public let endA: End
    public let endB: End
    private let aToB: BytePipe
    private let bToA: BytePipe

    public init(bufferCapacity: Int = 64 * 1024) {
        precondition(bufferCapacity > 0, "bufferCapacity must be positive")
        aToB = BytePipe(capacity: bufferCapacity)
        bToA = BytePipe(capacity: bufferCapacity)
        endA = End(outgoing: aToB, incoming: bToA)
        endB = End(outgoing: bToA, incoming: aToB)
        endA.peer = endB
        endB.peer = endA
    }

    /// Bytes that have crossed `direction` so far, including injected ones.
    public func captured(_ direction: Direction) async -> Data {
        await pipe(direction).captured
    }

    /// Writes raw bytes into `direction` as if the sending end had sent them (e.g. malformed
    /// frames), subject to the same backpressure.
    public func inject(_ data: Data, into direction: Direction) async throws {
        try await pipe(direction).write(data)
    }

    private func pipe(_ direction: Direction) -> BytePipe {
        direction == .aToB ? aToB : bToA
    }

    public final class End: ByteStreamConnection, @unchecked Sendable {
        // `peer` is written once in the pair's init before either end is shared.
        fileprivate weak var peer: End?
        private let outgoing: BytePipe
        private let incoming: BytePipe
        public let state: AsyncStream<ConnectionState>
        private let stateContinuation: AsyncStream<ConnectionState>.Continuation

        fileprivate init(outgoing: BytePipe, incoming: BytePipe) {
            self.outgoing = outgoing
            self.incoming = incoming
            (state, stateContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            stateContinuation.yield(.ready)
        }

        public func send(_ data: Data) async throws {
            try await outgoing.write(data)
        }

        public func receive() -> AsyncThrowingStream<Data, Error> {
            let incoming = incoming
            return AsyncThrowingStream { try await incoming.read() }
        }

        /// Abrupt teardown: both directions fail, this end reports `.cancelled`, the peer `.failed`.
        public func cancel() {
            let failure = ConnectionFailure("peer cancelled")
            let outgoing = outgoing, incoming = incoming
            Task {
                await outgoing.finish(with: failure)
                await incoming.finish(with: failure)
            }
            stateContinuation.yield(.cancelled)
            stateContinuation.finish()
            peer?.report(.failed(failure))
        }

        /// Orderly half-close of this end's sending direction; the peer's receive stream finishes
        /// and it reports `.closed`. This end can keep receiving.
        public func close() async {
            await outgoing.finish(with: nil)
            peer?.report(.closed)
        }

        fileprivate func report(_ newState: ConnectionState) {
            stateContinuation.yield(newState)
            if newState != .ready { stateContinuation.finish() }
        }
    }
}

/// One direction of an ``InMemoryConnectionPair``: a bounded FIFO with suspending writers.
actor BytePipe {
    private let capacity: Int
    private var buffer = Data()
    private(set) var captured = Data()
    /// `nil` while open; `.some(nil)` after an orderly close; `.some(error)` after a failure.
    private var ending: Error??
    private var waitingReader: CheckedContinuation<Void, Never>?
    private var waitingWriters: [CheckedContinuation<Void, Never>] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    func write(_ data: Data) async throws {
        var rest = data[...]
        while !rest.isEmpty {
            if let ending { throw ending ?? ConnectionFailure("write after close") }
            let space = capacity - buffer.count
            if space == 0 {
                await withCheckedContinuation { waitingWriters.append($0) }
                continue
            }
            let chunk = rest.prefix(space)
            buffer.append(contentsOf: chunk)
            captured.append(contentsOf: chunk)
            rest = rest.dropFirst(chunk.count)
            wakeReader()
        }
    }

    /// Returns everything buffered (freeing space for writers), or `nil` once closed and drained.
    func read() async throws -> Data? {
        while true {
            if !buffer.isEmpty {
                let data = buffer
                buffer = Data()
                wakeWriters()
                return data
            }
            if let ending {
                if let error = ending { throw error }
                return nil
            }
            await withCheckedContinuation { waitingReader = $0 }
        }
    }

    func finish(with error: Error?) {
        guard ending == nil else { return }
        ending = .some(error)
        wakeReader()
        wakeWriters()
    }

    private func wakeReader() {
        waitingReader?.resume()
        waitingReader = nil
    }

    private func wakeWriters() {
        let writers = waitingWriters
        waitingWriters = []
        writers.forEach { $0.resume() }
    }
}
