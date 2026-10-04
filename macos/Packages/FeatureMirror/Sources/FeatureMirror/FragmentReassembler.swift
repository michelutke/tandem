import Foundation

public enum MediaFrameError: Error, Equatable, Sendable {
    case malformedFrame
}

/// Reassembles one MediaFrame access unit from its fragments (SPEC §12). Memory grows per accepted
/// fragment, never from a declared total; any violation maps to MALFORMED_FRAME / FRAGMENT_VIOLATION.
public struct FragmentReassembler: Sendable {
    public static let maxFragmentCount: UInt32 = 8
    public static let maxFragmentBytes = 960 * 1024
    public static let maxAccessUnitBytes = 8 * 1024 * 1024

    private let maxBytes: Int
    private var pts: UInt64?
    private var count: UInt32 = 0
    private var nextIndex: UInt32 = 0
    private var buffer = Data()

    public init(maxBytes: Int = FragmentReassembler.maxAccessUnitBytes) {
        self.maxBytes = maxBytes
    }

    /// Returns the complete access unit once its last fragment arrives, `nil` while incomplete.
    public mutating func accept(
        pts: UInt64,
        fragmentIndex: UInt32,
        fragmentCount: UInt32,
        data: Data
    ) throws(MediaFrameError) -> Data? {
        guard data.count <= Self.maxFragmentBytes else { throw .malformedFrame }
        guard fragmentCount >= 1, fragmentCount <= Self.maxFragmentCount else { throw .malformedFrame }
        if let current = self.pts {
            guard current == pts, fragmentCount == count else { throw .malformedFrame }
        } else {
            self.pts = pts
            count = fragmentCount
        }
        guard fragmentIndex == nextIndex, buffer.count + data.count <= maxBytes else { throw .malformedFrame }
        buffer.append(data)
        nextIndex += 1
        guard nextIndex == count else { return nil }
        let complete = buffer
        reset()
        return complete
    }

    private mutating func reset() {
        pts = nil
        count = 0
        nextIndex = 0
        buffer = Data()
    }
}
