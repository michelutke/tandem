import Foundation
import TandemProtocol

/// Splits the media connection's byte stream into length-prefixed `MediaMessage`s (SPEC "Media
/// frames"). The 1 MiB frame cap is checked from the 4 prefix bytes alone, before buffering the body.
struct MediaMessageParser {
    static let maxFrameBytes = 1 << 20

    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// The next complete message, `nil` while one is still incomplete.
    mutating func nextMessage() throws(MediaFrameError) -> Tandem_V1_MediaMessage? {
        guard buffer.count >= 4 else { return nil }
        let prefix = buffer.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard prefix > 0, prefix <= UInt32(Self.maxFrameBytes) else { throw .malformedFrame }
        let length = Int(prefix)
        guard buffer.count >= 4 + length else { return nil }
        let body = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        guard let message = try? Tandem_V1_MediaMessage(serializedBytes: body), message.payload != nil else {
            throw .malformedFrame
        }
        return message
    }

    static func encode(_ message: Tandem_V1_MediaMessage) -> Data? {
        guard let body = try? message.serializedData() else { return nil }
        var frame = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }
}
