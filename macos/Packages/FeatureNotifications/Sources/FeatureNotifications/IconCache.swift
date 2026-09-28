import AppKit
import Foundation
import ImageIO
import TandemCrypto
import TandemProtocol
import TandemStore

/// Disk cache for received `IconData` (notify.proto, E30-01), keyed by
/// `packageName + versionCode` (icons are cached per app version, not per notification, E30-05).
/// Served to ``NotificationPresentationCoordinator`` (E30-07) and, in a future issue, the
/// paired-devices/app-list UI.
///
/// Conforms to ``PeerDataPurging`` so a composition root can register it with
/// `TandemStore/PeerDataPurgeRegistry` (E14-13): unpairing a phone deletes its cached icons.
/// `IconData` itself carries no peer identifier (notify.proto), so this actor keeps its own
/// in-memory peer -> cache-key index (mirroring ``NotificationPresentationCoordinator``'s own
/// `identifiersByPeer`) built from whichever peer's session frame delivered each icon
/// (``startNotificationPresentationReader``'s NOTIFY-channel reader forwards `IconData` frames
/// here). That index is not itself persisted to disk -- only the icon bytes are -- since it is
/// rebuilt as icons arrive again after a relaunch, same as the notification-identifier index.
public actor IconCache: PeerDataPurging {
    /// E01-22's cap: an `IconData` over this size is discarded and the placeholder used instead.
    public static let maxByteSize = 64 * 1024
    /// E01-22's cap: an `IconData` decoding to a larger pixel width or height is discarded and
    /// the placeholder used instead.
    public static let maxDimension = 256
    /// The generic placeholder file's name inside `directory`, exposed so a caller can recognize
    /// a returned placeholder URL without inspecting file contents.
    public static let placeholderFilename = "placeholder.png"

    private let directory: URL
    private var keysByPeer: [SpkiFingerprint: Set<String>] = [:]
    private var placeholderURL: URL?

    /// Creates (if needed) `directory` as this cache's on-disk store. Tests point this at a
    /// throwaway temporary directory rather than the real Application Support directory.
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Validates and stores `icon` on disk, recording it against `peer` for later
    /// ``purgeAll(peer:)``. Discards `icon` (no file written, nothing recorded) if its bytes
    /// exceed ``maxByteSize``, fail to decode as an image, or decode to pixel dimensions over
    /// ``maxDimension`` (E01-22) -- a subsequent ``iconURL(packageName:versionCode:)`` for the
    /// same key then falls back to the placeholder.
    public func store(_ icon: Tandem_V1_IconData, from peer: SpkiFingerprint) async {
        guard Self.isValid(icon.pngBytes) else { return }
        let key = Self.key(packageName: icon.packageName, versionCode: icon.versionCode)
        do {
            try icon.pngBytes.write(to: fileURL(for: key))
            keysByPeer[peer, default: []].insert(key)
        } catch {
            // Best-effort disk cache: a write failure just means the next lookup falls back to
            // the placeholder, same as an icon never received.
        }
    }

    /// The on-disk URL for the cached icon at `packageName` + `versionCode`, or a generic
    /// placeholder icon's URL if none is cached (not yet received, evicted, or discarded by
    /// ``store(_:from:)`` for being over-cap).
    public func iconURL(packageName: String, versionCode: Int64) async -> URL {
        let key = Self.key(packageName: packageName, versionCode: versionCode)
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return placeholder()
        }
        return url
    }

    /// ``PeerDataPurging`` conformance: deletes every icon recorded as received from `peer`. A
    /// no-op if `peer` has no cached icons (or already had everything purged).
    public func purgeAll(peer: SpkiFingerprint) async throws {
        guard let keys = keysByPeer.removeValue(forKey: peer) else { return }
        for key in keys {
            try? FileManager.default.removeItem(at: fileURL(for: key))
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).png")
    }

    private static func key(packageName: String, versionCode: Int64) -> String {
        "\(packageName)_\(versionCode)"
    }

    /// Decodes `pngBytes`' actual dimensions via `ImageIO` rather than trusting any size field
    /// the peer sent -- a lying peer could otherwise smuggle an oversized image past a naive
    /// check.
    private static func isValid(_ pngBytes: Data) -> Bool {
        guard !pngBytes.isEmpty, pngBytes.count <= maxByteSize else { return false }
        guard
            let source = CGImageSourceCreateWithData(pngBytes as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return false
        }
        return width <= maxDimension && height <= maxDimension
    }

    private func placeholder() -> URL {
        let url = directory.appendingPathComponent(Self.placeholderFilename)
        if placeholderURL == nil || !FileManager.default.fileExists(atPath: url.path) {
            if let data = Self.renderPlaceholderPNG() {
                try? data.write(to: url)
            }
            placeholderURL = url
        }
        return url
    }

    /// Renders a generic app placeholder (SF Symbol "questionmark.app") to PNG bytes. This repo
    /// has no existing placeholder-icon asset convention, so this renders one at runtime rather
    /// than adding an asset catalog to a package that otherwise has none.
    private static func renderPlaceholderPNG() -> Data? {
        guard let image = NSImage(
            systemSymbolName: "questionmark.app",
            accessibilityDescription: "Generic app icon"
        ) else {
            return nil
        }
        var rect = CGRect(x: 0, y: 0, width: maxDimension, height: maxDimension)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
