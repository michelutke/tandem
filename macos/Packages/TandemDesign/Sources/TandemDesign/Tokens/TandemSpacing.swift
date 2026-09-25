import CoreFoundation

/// Spacing tokens (ui-spec §3.3, E00-32): a 4 pt grid, screen padding of 20-28 pt on macOS glass
/// surfaces, and 12-16 pt row vertical padding.
public enum TandemSpacing {
    /// The base grid unit.
    public static let grid: CGFloat = 4
    public static let extraSmall: CGFloat = grid
    public static let small: CGFloat = grid * 2
    public static let medium: CGFloat = grid * 3
    public static let large: CGFloat = grid * 4
    public static let extraLarge: CGFloat = grid * 5

    /// `GlassPopover` padding (340 pt wide popover).
    public static let popoverPadding: CGFloat = 20
    /// `GlassWindow` / `GlassSheet` padding.
    public static let windowPadding: CGFloat = 28
    /// Row vertical padding (hairline rows, numbered rows).
    public static let rowVertical: CGFloat = 14
}
