import Foundation
@testable import TandemProtocol

/// A `FrameSource` (E11-04) backed by a fixed, already-in-memory byte buffer: exactly what a
/// fuzz input is. Each `read(exactly:)` call hands back up to `count` bytes and consumes them;
/// once the buffer is empty it returns an empty `Data`, the same "fewer bytes than asked, stream
/// closed" signal `FrameDecoder` expects from a real `FrameSource` at end of stream
/// (docs/protocol/SPEC.md #framing-and-envelope).
private final class FixedFrameSource: FrameSource, @unchecked Sendable {
    private var remaining: Data

    init(_ data: Data) {
        remaining = data
    }

    func read(exactly count: Int) async throws -> Data {
        guard !remaining.isEmpty else { return Data() }
        let take = min(count, remaining.count)
        let chunk = Data(remaining.prefix(take))
        remaining.removeFirst(take)
        return chunk
    }
}

/// Runs one `FrameDecoder.decode(from:)` call over `data`, discarding the result. This is the one
/// piece of logic shared by every harness over the frame/envelope parser (E15-14):
///   - the libFuzzer entry point (`fuzzer-entry/LLVMFuzzerEntry.swift`, built by `smoke.sh` with
///     `-sanitize=fuzzer,address`) calls it once per fuzz iteration;
///   - `SeedCorpusReplayTests` calls it once per `protocol/vectors/frame-encoding.json` vector, so
///     the seed corpus is replayed on every `swift test` — no sanitizer toolchain required.
/// A well-formed rejection (`DecodeResult.rejected`) is expected and not a failure; only a Swift
/// runtime trap (out-of-bounds access, force-unwrap, etc.) or, under ASan, a memory-safety
/// finding is. `FrameDecoder.decode` only ever throws for a transport failure, which
/// `FixedFrameSource` never raises, so the `try?` below only ever swallows a case that cannot
/// occur here — it is not masking real decoder errors, which surface as `.rejected`, not thrown.
public func fuzzOne(_ data: Data) {
    let source = FixedFrameSource(data)
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        _ = try? await FrameDecoder.decode(from: source)
        semaphore.signal()
    }
    semaphore.wait()
}

/// E71-02: treats `data` as serialized `Envelope` bytes and prepends the matching big-endian
/// length prefix, so every fuzz iteration reaches the Envelope protobuf decoder and the
/// channel/payload checks instead of being rejected on the prefix. Inputs that are empty or over
/// `FrameEncoder.maxEnvelopeBytes` are skipped (the prefix checks cover them).
public func fuzzOneEnvelope(_ data: Data) {
    guard !data.isEmpty, data.count <= FrameEncoder.maxEnvelopeBytes else { return }
    let length = UInt32(data.count)
    var frame = Data(capacity: 4 + data.count)
    for shift in [24, 16, 8, 0] {
        frame.append(UInt8(truncatingIfNeeded: length >> UInt32(shift)))
    }
    frame.append(data)
    fuzzOne(frame)
}
