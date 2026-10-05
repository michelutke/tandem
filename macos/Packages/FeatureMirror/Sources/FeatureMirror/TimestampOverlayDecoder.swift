/// Frame index and phone-side wall clock recovered from a timestamp overlay (E61-08).
public struct TimestampOverlay: Equatable, Sendable {
    public let frameIndex: UInt32
    public let clockMs: Int64

    public init(frameIndex: UInt32, clockMs: Int64) {
        self.frameIndex = frameIndex
        self.clockMs = clockMs
    }
}

/// Reads the overlay the Android `TimestampOverlayEncoder` burns into the top-left of each frame:
/// 96 cells of 8x8 px (32-bit frame index then 64-bit clock milliseconds, MSB first), white for 1
/// and black for 0. Samples each cell's centre against a mid-grey threshold.
public enum TimestampOverlayDecoder {
    static let cellSize = 8
    static let frameIndexBits = 32
    static let clockBits = 64
    static let threshold: UInt8 = 128

    /// Decodes a row-major 8-bit luma frame, or nil when it is too small to hold the overlay.
    public static func decode(luma: [UInt8], width: Int, height: Int) -> TimestampOverlay? {
        let totalBits = frameIndexBits + clockBits
        guard width >= totalBits * cellSize, height >= cellSize, luma.count >= width * height else { return nil }
        var frameIndex: UInt32 = 0
        var clock: UInt64 = 0
        for bit in 0..<totalBits {
            let column = bit * cellSize + cellSize / 2
            let isSet: UInt64 = luma[(cellSize / 2) * width + column] >= threshold ? 1 : 0
            if bit < frameIndexBits {
                frameIndex = frameIndex << 1 | UInt32(isSet)
            } else {
                clock = clock << 1 | isSet
            }
        }
        return TimestampOverlay(frameIndex: frameIndex, clockMs: Int64(bitPattern: clock))
    }
}
