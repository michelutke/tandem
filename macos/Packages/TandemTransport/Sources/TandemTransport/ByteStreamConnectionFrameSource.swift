import Foundation
import TandemProtocol

/// Adapts any ``ByteStreamConnection``'s `receive()` (E00-25) to `TandemProtocol`'s `FrameSource`
/// (E11-04) -- the production counterpart to `TandemProtocolTests`' own `InMemoryFrameSource`
/// (`TandemProtocol` may not depend on `TandemTransport`, so that adapter lives in tests; this one
/// lives here since `TandemTransport` may depend on `TandemProtocol`). Buffers leftover bytes
/// between `read(exactly:)` calls, since one `receive()` element can be more or fewer bytes than
/// the decoder asked for.
final class ByteStreamConnectionFrameSource: FrameSource, @unchecked Sendable {
    // Not actor-isolated: `AsyncIteratorProtocol.next()` is a non-Sendable mutating async method,
    // and a single instance is only ever driven by one caller at a time (one
    // `ChannelMultiplexer` reader loop per connection), exactly like `InMemoryFrameSource`.
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private var buffer = Data()

    init(_ connection: any ByteStreamConnection) {
        iterator = connection.receive().makeAsyncIterator()
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

    /// Returns `data` to the front of the buffer, so bytes read ahead to classify a connection are
    /// seen again by the reader that actually owns it.
    func pushBack(_ data: Data) {
        buffer = data + buffer
    }

    /// Bytes already read from the connection but not yet consumed by a `read(exactly:)` call.
    func takeBuffered() -> Data {
        defer { buffer.removeAll() }
        return buffer
    }
}
