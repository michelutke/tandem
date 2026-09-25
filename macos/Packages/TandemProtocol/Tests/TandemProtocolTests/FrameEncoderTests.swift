import CryptoKit
import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E11-03: Swift `FrameEncoder`, the macOS counterpart to Android's `FrameEncoder` (E11-01).
/// Frame = 4-byte big-endian length prefix (serialized Envelope byte count) + serialized
/// Envelope (docs/protocol/SPEC.md #framing-and-envelope). Tests send the encoded frame into an
/// `InMemoryConnectionPair` (E00-25) and read the per-direction capture, since `TandemProtocol`
/// itself may not depend on `TandemTransport` (see Package.swift).
struct FrameEncoderTests {
    @Test
    func encodeFrame_everyValidFrameVector_bytesEqualExpected() async throws {
        let manifest = try FrameEncodingVectorFixture.load()
        let validEntries = FrameEncodingVectorFixture.validEntries(in: manifest)
        #expect(!validEntries.isEmpty)

        for entry in validEntries {
            let expectedFrame = try FrameEncodingVectorFixture.frameBytes(for: entry)
            let envelopeBytes = try FrameEncodingVectorFixture.envelopeBytes(for: entry)
            let envelope = try Tandem_V1_Envelope(serializedBytes: envelopeBytes)

            let pair = InMemoryConnectionPair(bufferCapacity: expectedFrame.count + 8)
            let frame = try FrameEncoder.encode(envelope)
            try await pair.endA.send(frame)
            let captured = await pair.captured(.aToB)

            #expect(captured == expectedFrame, "vector \(entry.id)")

            if let expectedSha = entry.expected?.frameSha256 {
                let digest = SHA256.hash(data: captured)
                let actualSha = digest.map { String(format: "%02x", $0) }.joined()
                #expect(actualSha == expectedSha, "vector \(entry.id) frameSha256")
            }
        }
    }

    @Test
    func encodeFrame_lengthPrefix_isBigEndianEnvelopeByteCount() async throws {
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .status
        envelope.seq = 42
        envelope.ack = 41
        var status = Tandem_V1_DeviceStatus()
        status.batteryLevel = 76
        status.isCharging = true
        status.networkType = .cellular
        status.signalLevel = 3
        envelope.deviceStatus = status
        let envelopeBytes = try envelope.serializedData()

        let pair = InMemoryConnectionPair()
        let frame = try FrameEncoder.encode(envelope)
        try await pair.endA.send(frame)
        let captured = await pair.captured(.aToB)

        #expect(captured.count == 4 + envelopeBytes.count)
        let prefixBytes = [UInt8](captured.prefix(4))
        let lengthPrefix =
            UInt32(prefixBytes[0]) << 24 | UInt32(prefixBytes[1]) << 16 | UInt32(prefixBytes[2]) << 8
                | UInt32(prefixBytes[3])
        #expect(lengthPrefix == UInt32(envelopeBytes.count))
    }

    @Test
    func encodeFrame_envelopeExactly1MiB_written() async throws {
        let envelopeBytes = try WireBuilder.paddedRingEnvelope(totalBytes: FrameEncoder.maxEnvelopeBytes)
        #expect(envelopeBytes.count == FrameEncoder.maxEnvelopeBytes)
        let envelope = try Tandem_V1_Envelope(serializedBytes: envelopeBytes)

        let pair = InMemoryConnectionPair(bufferCapacity: FrameEncoder.maxEnvelopeBytes + 8)
        let frame = try FrameEncoder.encode(envelope)
        try await pair.endA.send(frame)
        let captured = await pair.captured(.aToB)

        #expect(captured.count == 4 + FrameEncoder.maxEnvelopeBytes)
        #expect(captured == frame)
    }

    @Test
    func encodeFrame_envelopeOneByteOver1MiB_throwsWithZeroBytesWritten() async throws {
        let envelopeBytes = try WireBuilder.paddedRingEnvelope(totalBytes: FrameEncoder.maxEnvelopeBytes + 1)
        #expect(envelopeBytes.count == FrameEncoder.maxEnvelopeBytes + 1)
        let envelope = try Tandem_V1_Envelope(serializedBytes: envelopeBytes)

        let pair = InMemoryConnectionPair(bufferCapacity: FrameEncoder.maxEnvelopeBytes + 8)
        #expect(throws: FrameError.tooLarge) {
            try FrameEncoder.encode(envelope)
        }
        let captured = await pair.captured(.aToB)
        #expect(captured.isEmpty)
    }
}
