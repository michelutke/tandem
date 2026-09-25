import SwiftUI

/// A font plus the letter-spacing (`tracking`) it is always paired with (ui-spec §3.2: "Letter-
/// spacing tightens with size").
public struct TandemTextStyle: Equatable, Sendable {
    public let font: Font
    public let tracking: CGFloat

    public init(font: Font, tracking: CGFloat) {
        self.font = font
        self.tracking = tracking
    }
}

/// Named font families (ui-spec §3.2): Inter Tight for UI text, JetBrains Mono for numbers that
/// are codes (pairing code, fingerprints, file sizes, row numbers). `Font.custom` falls back to
/// the system font when a family isn't installed, so this compiles and previews before the font
/// files themselves are bundled into the app target.
public enum TandemFontFamily {
    public static let interTight = "InterTight-Regular"
    public static let interTightSemibold = "InterTight-SemiBold"
    public static let interTightBold = "InterTight-Bold"
    public static let jetBrainsMono = "JetBrainsMono-Regular"
}

/// Type scale (ui-spec §3.2, E00-32). Every role below maps to exactly one table row.
public enum TandemTypography {
    /// Display numeral: ring centre, pairing code, timers. 64-96 / 400 / -3 tracking.
    public static func displayNumeral(size: CGFloat = 80) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.jetBrainsMono, size: size), tracking: -3)
    }

    /// Title pair, bold subject line ("Pixel 9."). 22-28 pt macOS / 700 / -1 tracking.
    public static func titlePairBold(size: CGFloat = 24) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTightBold, size: size), tracking: -1)
    }

    /// Title pair, regular state line ("Connected."). Same size as the bold line.
    public static func titlePairRegular(size: CGFloat = 24) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTight, size: size), tracking: -1)
    }

    /// Section title (Mac main window): "Messages." / "3 unread." 26 / 700+400 / -0.8 tracking.
    public static func sectionTitleBold(size: CGFloat = 26) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTightBold, size: size), tracking: -0.8)
    }

    /// Section title, regular weight.
    public static func sectionTitleRegular(size: CGFloat = 26) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTight, size: size), tracking: -0.8)
    }

    /// Row title. 16-17 / 600 / -0.3 tracking.
    public static func rowTitle(size: CGFloat = 16) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTightSemibold, size: size), tracking: -0.3)
    }

    /// Body. 13-15 / 400, line height 1.45 (applied by the caller via `.lineSpacing`).
    public static func body(size: CGFloat = 14) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTight, size: size), tracking: 0)
    }

    /// Meta: units, timestamps. 11-12 / 400.
    public static func meta(size: CGFloat = 12) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.interTight, size: size), tracking: 0)
    }

    /// Row numbers ("01", "02") and other meta text that is a code: meta size, mono.
    public static func metaMono(size: CGFloat = 12) -> TandemTextStyle {
        TandemTextStyle(font: .custom(TandemFontFamily.jetBrainsMono, size: size), tracking: 0)
    }
}

public extension View {
    /// Applies both the font and the tracking half of a ``TandemTextStyle`` token.
    func tandemTextStyle(_ style: TandemTextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
