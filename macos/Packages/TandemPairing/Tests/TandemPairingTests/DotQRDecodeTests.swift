import CoreImage
import SwiftUI
import TandemDesign
import Testing
@testable import TandemPairing

@MainActor
struct DotQRDecodeTests {
    private static let uri = "tandem://pair?v=1&fp=q83vEjRWeJq83vEjRWeJq83vEjRWeJq83vEjRWeJq8k"
        + "&s=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&a=192.168.178.42&p=47821&n=Miggi%E2%80%99s%20MacBook%20Pro"

    private func renderedImage(side: CGFloat) throws -> CGImage {
        let image = try #require(QrCodeImage.generate(message: Self.uri))
        let view = DotQR(modules: QrCodeImage.modules(for: image)).frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    private func decode(_ image: CGImage) -> [String] {
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options)
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    private func downscaled(_ image: CGImage, to side: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return try #require(context.makeImage())
    }

    @Test func dotQR_renderedPairingUri_decodesToExactUri() throws {
        #expect(decode(try renderedImage(side: 280)) == [Self.uri])
    }

    @Test func dotQR_renderedPairingUriDownscaledTo200_decodesToExactUri() throws {
        let small = try downscaled(try renderedImage(side: 280), to: 200)
        #expect(decode(small) == [Self.uri])
    }

    @Test func dotQR_renderedFinderPattern_isSolidRingAndCentre() throws {
        let image = try #require(QrCodeImage.generate(message: Self.uri))
        let modules = QrCodeImage.modules(for: image)
        let rendered = try renderedImage(side: 560)
        let pixels = try grayscale(rendered)
        let total = CGFloat(modules.count + DotQR.quietZoneModules * 2)
        let module = CGFloat(rendered.width) / total
        func isDark(_ col: CGFloat, _ row: CGFloat) -> Bool {
            let pixelX = Int((col + CGFloat(DotQR.quietZoneModules)) * module)
            let pixelY = Int((row + CGFloat(DotQR.quietZoneModules)) * module)
            return pixels[pixelY * rendered.width + pixelX] < 128
        }
        for step in stride(from: 0.5, through: 6.5, by: 0.5) {
            for (col, row) in [(step, 0.5), (step, 6.5), (0.5, step), (6.5, step)] {
                #expect(isDark(col, row), "ring gap at (\(col), \(row))")
            }
        }
        for step in stride(from: 2.5, through: 4.5, by: 0.5) {
            for other in stride(from: 2.5, through: 4.5, by: 0.5) {
                #expect(isDark(step, other), "centre gap at (\(step), \(other))")
            }
        }
    }

    private func grayscale(_ image: CGImage) throws -> [UInt8] {
        var gray = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try #require(CGContext(
            data: &gray, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return gray
    }
}
