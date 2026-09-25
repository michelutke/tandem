import SwiftUI

/// Colour tokens (ui-spec §3.1, E00-32). Colour is a signal, never decoration: `signal` and
/// `alert` are the only accents anywhere in the app; every other surface is one of these greys.
/// Feature code must reference these tokens instead of constructing `Color`/`NSColor` literals
/// (checked by `tools/lint/literal-color-check.rb`).
public enum TandemColor {
    /// Primary text, lit dots, filled buttons.
    public static let ink = Color(hex: 0x0A0A0A)
    /// Secondary text, state lines, units, row numbers. >= 4.5:1 on `paper` at >= 14 pt only;
    /// use `ink` for smaller body text (ui-spec §11).
    public static let ink2 = Color(hex: 0x8A8A8A)
    /// Backgrounds / glass tint base.
    public static let paper = Color(hex: 0xFFFFFF)
    /// Connected, healthy, current position, "done".
    public static let signal = Color(hex: 0x00D65A)
    /// Trust failure, destructive actions, send failures.
    public static let alert = Color(hex: 0xFF3B30)
    /// Hairlines and 10% overlays (`#0A0A0A1A`). Use ``line(increasedContrast:)`` when the
    /// system "Increase contrast" setting is on.
    public static let line = Color(hex: 0x0A0A0A, alpha: 0x1A)
    /// Unlit dots (`#0A0A0A1F`, 12%). Use ``lineUnlit(increasedContrast:)`` when the system
    /// "Increase contrast" setting is on.
    public static let lineUnlit = Color(hex: 0x0A0A0A, alpha: 0x1F)

    /// `line`, boosted to ~25% opacity under "Increase contrast" (ui-spec §5.1: components honour
    /// Increase Contrast).
    public static func line(increasedContrast: Bool) -> Color {
        increasedContrast ? Color(hex: 0x0A0A0A, alpha: 0x40) : line
    }

    /// `lineUnlit`, boosted to ~25% opacity under "Increase contrast".
    public static func lineUnlit(increasedContrast: Bool) -> Color {
        increasedContrast ? Color(hex: 0x0A0A0A, alpha: 0x40) : lineUnlit
    }
}

extension Color {
    /// `hex` is a 24-bit `0xRRGGBB` value; `alpha` is an 8-bit channel (`0xFF` = opaque). Internal
    /// to this package: tokens above are the only place literal colour values may appear.
    init(hex: UInt32, alpha: UInt8 = 0xFF) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: Double(alpha) / 255)
    }
}
