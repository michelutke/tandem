import AppKit

/// Production ``PasteboardSource`` over `NSPasteboard.general` -- the only type in this package
/// permitted to touch the real pasteboard (E31-02 seam rule).
public final class NSPasteboardSource: PasteboardSource {
    public init() {}

    public var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    public func types() -> [NSPasteboard.PasteboardType] {
        NSPasteboard.general.types ?? []
    }

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        NSPasteboard.general.string(forType: type)
    }

    @discardableResult
    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        NSPasteboard.general.setString(string, forType: type)
    }
}
