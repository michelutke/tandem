import CoreGraphics
import Observation
import TandemProtocol

@MainActor
@Observable
public final class MirrorWindowModel {
    public private(set) var streamSize: CGSize
    public private(set) var windowSize: CGSize

    public var contentRect: CGRect {
        LetterboxLayout.contentRect(stream: streamSize, window: windowSize)
    }

    public init(streamSize: CGSize, windowSize: CGSize) {
        self.streamSize = streamSize
        self.windowSize = windowSize
    }

    public func windowResized(_ size: CGSize) {
        windowSize = size
    }

    public func mediaFormatChanged(width: Int, height: Int) {
        streamSize = CGSize(width: width, height: height)
    }

    public func rotationChanged(_ orientation: Tandem_V1_Orientation) {
        let isLandscape: Bool
        switch orientation {
        case .landscape, .reverseLandscape: isLandscape = true
        case .portrait, .reversePortrait: isLandscape = false
        case .unspecified, .UNRECOGNIZED: return
        }
        guard (streamSize.width > streamSize.height) != isLandscape else { return }
        streamSize = CGSize(width: streamSize.height, height: streamSize.width)
    }
}
