import Foundation

public enum AnnexBError: Error, Equatable, Sendable {
    case noStartCode
    case zeroLengthNal
    case tooLarge
}

public struct NALUnit: Equatable, Sendable {
    public let bytes: Data

    public init(bytes: Data) {
        self.bytes = bytes
    }

    public var h264Type: UInt8 { (bytes.first ?? 0) & 0x1F }
    public var hevcType: UInt8 { ((bytes.first ?? 0) >> 1) & 0x3F }
}

/// Splits an Annex-B access unit at 3- and 4-byte start codes. The input comes from the network,
/// so every index is bounds-checked and input over the 8 MiB access-unit cap is rejected.
public enum AnnexBParser {
    public static let maxInputBytes = 8 * 1024 * 1024

    public static func parse(_ data: Data) throws(AnnexBError) -> [NALUnit] {
        guard data.count <= maxInputBytes else { throw .tooLarge }
        let bytes = [UInt8](data)
        let starts = startCodeRanges(in: bytes)
        guard let first = starts.first, first.lowerBound == 0 else { throw .noStartCode }
        var units: [NALUnit] = []
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1].lowerBound : bytes.count
            let payload = bytes[start.upperBound..<end]
            guard !payload.isEmpty else { throw .zeroLengthNal }
            units.append(NALUnit(bytes: Data(payload)))
        }
        return units
    }

    /// Each range covers one start code including a leading zero byte when it is 4 bytes long.
    private static func startCodeRanges(in bytes: [UInt8]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                let lower = index > 0 && bytes[index - 1] == 0 && ranges.last?.upperBound != index ? index - 1 : index
                ranges.append(lower..<(index + 3))
                index += 3
            } else {
                index += 1
            }
        }
        return ranges
    }
}
