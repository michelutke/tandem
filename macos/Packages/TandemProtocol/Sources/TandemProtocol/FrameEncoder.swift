import Foundation

/// Errors ``FrameEncoder`` can throw (docs/protocol/SPEC.md #framing-and-envelope).
enum FrameError: Error, Sendable, Equatable {
    /// The serialized Envelope exceeds `FrameEncoder.maxEnvelopeBytes` (1 MiB). Nothing is
    /// written to the frame when this is thrown.
    case tooLarge
}

/// Encodes a `Tandem_V1_Envelope` into a frame: a 4-byte big-endian length prefix (the
/// serialized Envelope's byte count, excluding the prefix itself) followed by the serialized
/// Envelope (docs/protocol/SPEC.md #framing-and-envelope). Swift counterpart to the Android
/// `FrameEncoder` (E11-01); `Tandem_V1_Envelope` is internal to this module (the generated code
/// is not built with `Visibility=Public`), so this stays internal too.
enum FrameEncoder {
    /// 1 MiB (2^20), the maximum serialized Envelope length the length prefix can carry
    /// (docs/protocol/SPEC.md #framing-and-envelope).
    static let maxEnvelopeBytes = 1_048_576

    static func encode(_ envelope: Tandem_V1_Envelope) throws -> Data {
        let envelopeBytes = try envelope.serializedData()
        guard envelopeBytes.count <= maxEnvelopeBytes else {
            throw FrameError.tooLarge
        }

        let length = UInt32(envelopeBytes.count)
        var frame = Data(capacity: 4 + envelopeBytes.count)
        frame.append(UInt8(truncatingIfNeeded: length >> 24))
        frame.append(UInt8(truncatingIfNeeded: length >> 16))
        frame.append(UInt8(truncatingIfNeeded: length >> 8))
        frame.append(UInt8(truncatingIfNeeded: length))
        frame.append(envelopeBytes)
        return frame
    }
}
