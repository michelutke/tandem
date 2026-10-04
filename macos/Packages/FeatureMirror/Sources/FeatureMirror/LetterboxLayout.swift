import CoreGraphics

/// Aspect-fit content rect shared with the Android `CoordinateMapper` geometry (E62-03).
public enum LetterboxLayout {
    public static func contentRect(stream: CGSize, window: CGSize) -> CGRect {
        guard stream.width > 0, stream.height > 0, window.width > 0, window.height > 0 else { return .zero }
        let scale = min(window.width / stream.width, window.height / stream.height)
        let width = stream.width * scale
        let height = stream.height * scale
        return CGRect(x: (window.width - width) / 2, y: (window.height - height) / 2, width: width, height: height)
    }
}
