import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E11-04: Swift `FrameDecoder`, the macOS counterpart to Android's `FrameDecoder` (E11-02).
/// Every vector in `protocol/vectors/frame-encoding.json` (E01-19) is run through the decoder:
/// valid vectors must decode to the expected `Envelope`; invalid vectors must reject with
/// `CloseCode.malformedFrame` and the vector's tagged local reason
/// (docs/protocol/SPEC.md #framing-and-envelope "Rejection cases"). Bytes are delivered through
/// an `InMemoryConnectionPair` (E00-25) adapted to `FrameSource` by `InMemoryFrameSource`, since
/// `TandemProtocol` itself may not depend on `TandemTransport` (see Package.swift).
struct FrameDecoderTests {
    @Test
    func decodeFrame_everyValidFrameVector_decodesToExpectedEnvelope() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let validEntries = FrameEncodingVectorFixture.validEntries(in: manifest)
        #expect(!validEntries.isEmpty)

        for entry in validEntries {
            guard let expected = entry.expected else {
                Issue.record("vector \(entry.id) has no expected output")
                continue
            }
            let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)
            let result = try await decode(frame)

            guard case .frame(let envelope) = result else {
                Issue.record("vector \(entry.id) did not decode to a frame: \(String(describing: result))")
                continue
            }
            let expectedChannelValue = FrameEncodingVectorFixture.channelValues[expected.channel]
            #expect(envelope.channel.rawValue == expectedChannelValue, "vector \(entry.id)")
            #expect(envelope.seq == expected.seq, "vector \(entry.id)")
            #expect(envelope.ack == expected.ack, "vector \(entry.id)")
            #expect(payloadLabel(envelope) == expected.payload, "vector \(entry.id)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func decodeFrame_declaredLengthOver1MiB_closesTooLargeAfterPrefixOnly() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        for id in ["frame-oversize-plus-one", "frame-bad-length-0xffffffff"] {
            let entry = try #require(manifest.vectors.first { $0.id == id })
            let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)
            #expect(frame.count == 4, "vector \(id) fixture should supply only the 4 prefix bytes")

            // Trailing bytes follow and the stream stays open, so a decoder that read past the
            // prefix would either consume them or block (caught by the time limit).
            let trailing = Data([0xAA, 0xBB, 0xCC])
            let pair = InMemoryConnectionPair()
            try await pair.endA.send(frame + trailing)
            let counting = CountingFrameSource(wrapping: InMemoryFrameSource(pair.endB))

            let result = try await FrameDecoder.decode(from: counting)

            #expect(result == .rejected(.malformedFrame, .tooLarge), "vector \(id)")
            #expect(counting.totalBytesRead == 4, "vector \(id) must not read past the length prefix")
            let remaining = try await counting.read(exactly: trailing.count)
            #expect(remaining == trailing, "vector \(id) trailing bytes must remain unread")
        }
    }

    @Test
    func decodeFrame_declaredLengthZero_closesBadLength() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let entry = try #require(manifest.vectors.first { $0.id == "frame-bad-length-zero" })
        let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)

        let result = try await decode(frame)

        #expect(result == .rejected(.malformedFrame, .badLength))
    }

    @Test
    func decodeFrame_eofMidPrefixOrPayload_closesTruncated() async throws {
        // Mid-prefix: the connection closes after only 2 of the 4 length-prefix bytes arrive.
        let midPrefixResult = try await decode(Data([0x00, 0x00]))
        #expect(midPrefixResult == .rejected(.malformedFrame, .truncated))

        // Mid-payload: a well-formed 17-byte envelope's frame, delivered one byte short.
        let manifest = try FrameEncodingVectorFixture.load()
        let entry = try #require(manifest.vectors.first { $0.id == "frame-truncated" })
        let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)

        let midPayloadResult = try await decode(frame)

        #expect(midPayloadResult == .rejected(.malformedFrame, .truncated))
    }

    @Test
    func decodeFrame_cleanCloseAtFrameBoundary_returnsNilNotTruncated() async throws {
        // No bytes at all arrive before the peer closes: SPEC.md #framing-and-envelope says this
        // is an ordinary connection close, not a TRUNCATED rejection.
        let result = try await decode(Data())

        #expect(result == nil)
    }

    @Test
    func decodeFrame_garbagePayload_closesDecodeFailedNoEnvelopeEmitted() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let entry = try #require(manifest.vectors.first { $0.id == "frame-decode-failed" })
        let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)

        let result = try await decode(frame)

        #expect(result == .rejected(.malformedFrame, .decodeFailed))
    }

    @Test
    func decodeFrame_unknownChannelValue_closesUnknownChannel() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let entry = try #require(manifest.vectors.first { $0.id == "frame-unknown-channel" })
        let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)

        let result = try await decode(frame)

        #expect(result == .rejected(.malformedFrame, .unknownChannel))
    }

    @Test
    func decodeFrame_unknownPayloadType_closesUnknownPayloadType() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let entry = try #require(manifest.vectors.first { $0.id == "frame-unknown-payload-type" })
        let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)

        let result = try await decode(frame)

        #expect(result == .rejected(.malformedFrame, .unknownPayloadType))
    }

    @Test
    func decodeFrame_everyInvalidFrameVector_rejectsWithTaggedReason() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let invalidEntries = FrameEncodingVectorFixture.invalidEntries(in: manifest)
        #expect(!invalidEntries.isEmpty)

        for entry in invalidEntries {
            guard let closeCode = entry.closeCode, let localReason = entry.localReason else {
                Issue.record("vector \(entry.id) has no closeCode/localReason")
                continue
            }
            #expect(closeCode == "MALFORMED_FRAME", "vector \(entry.id)")
            guard let reason = malformedFrameReason(named: localReason) else {
                Issue.record("vector \(entry.id): unrecognized localReason \(localReason)")
                continue
            }
            let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)

            let result = try await decode(frame)

            #expect(result == .rejected(.malformedFrame, reason), "vector \(entry.id)")
        }
    }

    private func payloadLabel(_ envelope: Tandem_V1_Envelope) -> String {
        switch envelope.payload {
        case .ring?: return "ring"
        case .deviceStatus?: return "deviceStatus"
        case nil: return "unset"
        }
    }

    private func malformedFrameReason(named name: String) -> MalformedFrameReason? {
        switch name {
        case "TOO_LARGE": return .tooLarge
        case "BAD_LENGTH": return .badLength
        case "TRUNCATED": return .truncated
        case "DECODE_FAILED": return .decodeFailed
        case "UNKNOWN_CHANNEL": return .unknownChannel
        case "UNKNOWN_PAYLOAD_TYPE": return .unknownPayloadType
        default: return nil
        }
    }

    /// Sends `bytes` from `endA` to `endB`, closes `endA`'s sending direction, and decodes one
    /// frame from `endB`. The pair's buffer is sized to `bytes` (e.g. the exactly-1-MiB vector)
    /// so `send` never suspends waiting for a reader that only starts afterward.
    private func decode(_ bytes: Data) async throws -> DecodeResult? {
        let pair = InMemoryConnectionPair(bufferCapacity: bytes.count + 8)
        try await pair.endA.send(bytes)
        await pair.endA.close()
        return try await FrameDecoder.decode(from: InMemoryFrameSource(pair.endB))
    }
}
