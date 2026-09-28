import AppKit
import Foundation
import Testing
import TandemCrypto
@testable import FeatureNotifications
@testable import TandemProtocol

@Suite struct IconCacheTests {
    /// A valid, tiny (1x1) PNG -- well under both E01-22 caps -- so tests exercise real
    /// `ImageIO` decoding rather than a hand-rolled fixture.
    private static let validPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    private static func validPNGBytes() throws -> Data {
        try #require(Data(base64Encoded: Self.validPNGBase64))
    }

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: 32))
    }

    private static func makeCache() throws -> (IconCache, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-icon-cache-test-\(UUID().uuidString)")
        let cache = try IconCache(directory: directory)
        return (cache, directory)
    }

    private static func icon(packageName: String, versionCode: Int64, pngBytes: Data) -> Tandem_V1_IconData {
        var icon = Tandem_V1_IconData()
        icon.packageName = packageName
        icon.versionCode = versionCode
        icon.pngBytes = pngBytes
        return icon
    }

    @Test func iconCache_storedIconNewCacheInstance_returnsSameBytes() async throws {
        let (cache, directory) = try Self.makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let peer = try Self.fingerprint(0x01)
        let pngBytes = try Self.validPNGBytes()
        let icon = Self.icon(packageName: "com.example.app", versionCode: 3, pngBytes: pngBytes)

        await cache.store(icon, from: peer)

        let freshCache = try IconCache(directory: directory)
        let url = await freshCache.iconURL(packageName: "com.example.app", versionCode: 3)
        let bytes = try Data(contentsOf: url)

        #expect(bytes == pngBytes)
        #expect(url.lastPathComponent != IconCache.placeholderFilename)
    }

    @Test func iconCache_unknownPackageVersion_returnsPlaceholder() async throws {
        let (cache, directory) = try Self.makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = await cache.iconURL(packageName: "com.unknown.app", versionCode: 1)

        #expect(url.lastPathComponent == IconCache.placeholderFilename)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func iconCache_peerUnpaired_iconsForPeerDeleted() async throws {
        let (cache, directory) = try Self.makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let peerA = try Self.fingerprint(0x02)
        let peerB = try Self.fingerprint(0x03)
        let pngBytes = try Self.validPNGBytes()
        let iconA = Self.icon(packageName: "com.example.a", versionCode: 1, pngBytes: pngBytes)
        let iconB = Self.icon(packageName: "com.example.b", versionCode: 1, pngBytes: pngBytes)

        await cache.store(iconA, from: peerA)
        await cache.store(iconB, from: peerB)

        try await cache.purgeAll(peer: peerA)

        let urlA = await cache.iconURL(packageName: "com.example.a", versionCode: 1)
        let urlB = await cache.iconURL(packageName: "com.example.b", versionCode: 1)

        #expect(urlA.lastPathComponent == IconCache.placeholderFilename)
        #expect(urlB.lastPathComponent != IconCache.placeholderFilename)
    }

    @Test func iconCache_iconOver64KiB_discardedPlaceholderUsed() async throws {
        let (cache, directory) = try Self.makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let peer = try Self.fingerprint(0x04)
        let oversized = Data(repeating: 0xFF, count: IconCache.maxByteSize + 1)
        let icon = Self.icon(packageName: "com.example.big", versionCode: 1, pngBytes: oversized)

        await cache.store(icon, from: peer)

        let url = await cache.iconURL(packageName: "com.example.big", versionCode: 1)
        #expect(url.lastPathComponent == IconCache.placeholderFilename)
    }

    @Test func iconCache_iconOverPixelCap_discardedPlaceholderUsed() async throws {
        let (cache, directory) = try Self.makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let peer = try Self.fingerprint(0x05)
        // 300x300, well within the byte cap but over the 256x256 pixel cap (E01-22): a lying
        // size field must not bypass the real dimension check.
        let oversizedDimensions = try Self.renderPNG(width: 300, height: 300)
        let icon = Self.icon(packageName: "com.example.wide", versionCode: 1, pngBytes: oversizedDimensions)

        await cache.store(icon, from: peer)

        let url = await cache.iconURL(packageName: "com.example.wide", versionCode: 1)
        #expect(url.lastPathComponent == IconCache.placeholderFilename)
    }

    private static func renderPNG(width: Int, height: Int) throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
