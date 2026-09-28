import AppKit

/// Seam over `NSPasteboard.general` (E31-02): abstracts every pasteboard read/write
/// ``PasteboardPoller`` and the eventual clipboard-sync send/receive paths need, so
/// ``NSPasteboardSource`` is the only type in this package permitted to touch the real
/// pasteboard. `FeatureClipboardTests`' own `FakePasteboardSource` exposes a settable
/// `changeCount`/`typesToReturn` in its place for tests.
public protocol PasteboardSource: Sendable {
    /// `NSPasteboard.general.changeCount`'s own contract: increments on every pasteboard write,
    /// from any process -- the seam ``PasteboardPoller`` polls to detect a change.
    var changeCount: Int { get }

    /// The types available on the current pasteboard item.
    func types() -> [NSPasteboard.PasteboardType]

    /// The string content for a given type, if the current pasteboard item has one.
    func string(forType type: NSPasteboard.PasteboardType) -> String?

    /// Writes `string` for `type` on the pasteboard, mirroring `NSPasteboard.setString(_:forType:)`.
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
}
