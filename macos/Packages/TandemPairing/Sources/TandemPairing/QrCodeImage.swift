import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Renders a pairing QR payload URI as a `CIImage` via `CIQRCodeGenerator` (E14-11 acceptance:
/// "The rendered QR image (CIQRCodeGenerator) decodes via CIDetector to exactly the current
/// window payload") and extracts its module grid for ``DotQR``.
public enum QrCodeImage {
    /// Balances symbol size against scan robustness; `CIQRCodeGenerator` supports `"L"`, `"M"`,
    /// `"Q"`, `"H"`.
    public static let correctionLevel = "M"

    /// `CIQRCodeGenerator`'s own output always carries exactly this many quiet-zone modules on
    /// every side (verified empirically against its rendered pixel grid) -- stripped by
    /// ``modules(for:)`` since ``DotQR`` supplies its own >= 4-module quiet zone.
    static let builtInQuietZoneModules = 1

    /// `nil` only if Core Image itself fails to produce an output image.
    public static func generate(message: String) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = correctionLevel
        return filter.outputImage
    }

    /// `modules[row][col]` is `true` for a dark module, with `image`'s built-in quiet zone
    /// stripped. Empty if `image`'s extent isn't square or is too small to hold one.
    public static func modules(for image: CIImage) -> [[Bool]] {
        let extent = image.extent
        let totalSize = Int(extent.width.rounded())
        guard totalSize > builtInQuietZoneModules * 2, totalSize == Int(extent.height.rounded()) else {
            return []
        }

        let context = CIContext(options: [.workingColorSpace: NSNull()])
        var pixels = [UInt8](repeating: 0, count: totalSize * totalSize * 4)
        context.render(
            image, toBitmap: &pixels, rowBytes: totalSize * 4, bounds: extent, format: .RGBA8, colorSpace: nil
        )

        let symbolSize = totalSize - builtInQuietZoneModules * 2
        return (0..<symbolSize).map { row in
            (0..<symbolSize).map { col in
                let pixelIndex = ((row + builtInQuietZoneModules) * totalSize + (col + builtInQuietZoneModules)) * 4
                return pixels[pixelIndex] < 128
            }
        }
    }
}
