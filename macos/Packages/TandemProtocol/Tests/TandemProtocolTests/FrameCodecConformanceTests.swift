import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

extension Tag {
    /// Marks the dedicated E11-12 conformance suite so a future runner (E15-02/E15-03) can select
    /// it independently of the ordinary encoder/decoder unit tests.
    @Tag static var conformance: Self
}

/// E11-12: Swift equivalent of Android's E11-11. Every vector in `protocol/vectors/frame-encoding.json`
/// (discovered via `FrameVectorLoader`, E01-19) is run end-to-end through the real `FrameDecoder`/
/// `FrameEncoder`: valid vectors must decode then re-encode back to the exact original frame bytes;
/// invalid vectors must be rejected with the vector's tagged close code. Distinct from
/// `FrameEncoderTests`/`FrameDecoderTests` (E11-03/E11-04), which check encode-only and decode-only
/// against expected values but not a full round trip.
struct FrameCodecConformanceTests {
    @Test(.tags(.conformance))
    func swiftFrameCodec_everyValidFrameVector_roundTripsToVectorBytes() async throws {
        let manifest = try FrameVectorLoader.loadDefault()
        let validEntries = FrameEncodingVectorFixture.validEntries(in: manifest)
        #expect(!validEntries.isEmpty)

        var records: [ConformanceReportWriter.Record] = []
        for entry in validEntries {
            let expectedFrame = try FrameEncodingVectorFixture.frameBytes(for: entry)
            let decoded = try await decodeFrame(expectedFrame)

            guard case .frame(let envelope) = decoded else {
                records.append(ConformanceReportWriter.Record(
                    vectorId: entry.id, outcome: "fail",
                    expected: expectedFrame.conformanceHex, actual: "decode-rejected: \(String(describing: decoded))"
                ))
                Issue.record("vector \(entry.id) did not decode to a frame: \(String(describing: decoded))")
                continue
            }

            let reencoded = try FrameEncoder.encode(envelope)
            let passed = reencoded == expectedFrame
            records.append(ConformanceReportWriter.Record(
                vectorId: entry.id, outcome: passed ? "pass" : "fail",
                expected: expectedFrame.conformanceHex, actual: reencoded.conformanceHex
            ))
            #expect(passed, "vector \(entry.id)")
        }
        try ConformanceReportWriter.write(records, filename: "frame-codec-valid.json")
    }

    @Test(.tags(.conformance))
    func swiftFrameCodec_everyInvalidFrameVector_rejectedWithTaggedCloseCode() async throws {
        let manifest = try FrameVectorLoader.loadDefault()
        let invalidEntries = FrameEncodingVectorFixture.invalidEntries(in: manifest)
        #expect(!invalidEntries.isEmpty)

        var records: [ConformanceReportWriter.Record] = []
        for entry in invalidEntries {
            guard let closeCode = entry.closeCode, let localReason = entry.localReason else {
                Issue.record("vector \(entry.id) has no closeCode/localReason")
                continue
            }
            #expect(closeCode == "MALFORMED_FRAME", "vector \(entry.id)")

            let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)
            let result = try await decodeFrame(frame)

            let passed: Bool
            let actualDescription: String
            if case .rejected(let code, let reason) = result,
               code == .malformedFrame, reasonName(reason) == localReason {
                passed = true
                actualDescription = "MALFORMED_FRAME:\(localReason)"
            } else {
                passed = false
                actualDescription = String(describing: result)
            }
            records.append(ConformanceReportWriter.Record(
                vectorId: entry.id, outcome: passed ? "pass" : "fail",
                expected: "\(closeCode):\(localReason)", actual: actualDescription
            ))
            #expect(passed, "vector \(entry.id)")
        }
        try ConformanceReportWriter.write(records, filename: "frame-codec-invalid.json")
    }

    private func reasonName(_ reason: MalformedFrameReason) -> String {
        switch reason {
        case .tooLarge: return "TOO_LARGE"
        case .badLength: return "BAD_LENGTH"
        case .truncated: return "TRUNCATED"
        case .decodeFailed: return "DECODE_FAILED"
        case .unknownChannel: return "UNKNOWN_CHANNEL"
        case .unknownPayloadType: return "UNKNOWN_PAYLOAD_TYPE"
        case .seqRegression: return "SEQ_REGRESSION"
        case .seqGapTooLarge: return "SEQ_GAP_TOO_LARGE"
        }
    }

    /// Sends `bytes` through a real `InMemoryConnectionPair` (E00-25) into `FrameDecoder`, exactly
    /// as `FrameDecoderTests`'s private helper does.
    private func decodeFrame(_ bytes: Data) async throws -> DecodeResult? {
        let pair = InMemoryConnectionPair(bufferCapacity: bytes.count + 8)
        try await pair.endA.send(bytes)
        await pair.endA.close()
        return try await FrameDecoder.decode(from: InMemoryFrameSource(pair.endB))
    }
}

private extension Data {
    var conformanceHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
