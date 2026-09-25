import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// Adapts an `InMemoryConnectionPair.End`'s `receive()` (E00-25) to ``FrameDecoder``'s
/// `FrameSource` (E11-04). `TandemProtocol` may not depend on `TandemTransport`, so this adapter
/// lives in tests rather than in the package itself. Buffers leftover bytes between
/// `read(exactly:)` calls, since one `receive()` element can be more or fewer bytes than the
/// decoder asked for.
final class InMemoryFrameSource: FrameSource, @unchecked Sendable {
    // Not actor-isolated: `AsyncIteratorProtocol.next()` is a non-Sendable mutating async
    // method, so an actor can't safely hand its stored iterator across the isolation boundary
    // to call it. Safe here because, like `InMemoryConnectionPair.End`, a single instance is
    // only ever driven by one caller at a time (one `FrameDecoder.decode(from:)` call).
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private var buffer = Data()

    init(_ end: InMemoryConnectionPair.End) {
        iterator = end.receive().makeAsyncIterator()
    }

    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            guard let chunk = try await iterator.next() else {
                let collected = buffer
                buffer.removeAll()
                return collected
            }
            buffer.append(chunk)
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }
}

/// Wraps a ``FrameSource``, counting the total bytes it has returned across every
/// `read(exactly:)` call, so a test can assert exactly how much of the stream a decode consumed
/// (e.g. "only the 4 prefix bytes" for an oversize `length_prefix`).
final class CountingFrameSource: FrameSource, @unchecked Sendable {
    private let wrapped: FrameSource
    private(set) var totalBytesRead = 0

    init(wrapping wrapped: FrameSource) {
        self.wrapped = wrapped
    }

    func read(exactly count: Int) async throws -> Data {
        let data = try await wrapped.read(exactly: count)
        totalBytesRead += data.count
        return data
    }
}
