import CoreFoundation

/// Corner-radius tokens (ui-spec §3.3, E00-32).
public enum TandemRadius {
    /// Popover / window corner radius.
    public static let popoverWindow: CGFloat = 26
    /// `GlassSheet` / modal corner radius.
    public static let sheet: CGFloat = 32
}
