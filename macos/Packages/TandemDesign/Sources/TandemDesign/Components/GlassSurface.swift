import SwiftUI

/// Which background a glass surface should draw (ui-spec §5.1: "Honours Reduce Transparency
/// (solid fallback)"). Pulled out as a pure function so it is unit-testable without needing a
/// hosted view / accessibility environment.
public enum GlassSurfaceStyle: Equatable, Sendable {
    case glass
    case solidPaper

    public static func resolve(reduceTransparency: Bool) -> GlassSurfaceStyle {
        reduceTransparency ? .solidPaper : .glass
    }
}

/// System Liquid Glass material on macOS 26, an `.ultraThinMaterial` fallback on macOS 15-25 (no
/// custom blur code either way, per ui-spec §4 motion note 05), and a solid `paper` fill when
/// Reduce Transparency is on. Backs `GlassPopover`, `GlassWindow`, `GlassSidebar` and `GlassSheet`.
struct GlassBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(background)
    }

    @ViewBuilder
    private var background: some View {
        switch GlassSurfaceStyle.resolve(reduceTransparency: reduceTransparency) {
        case .solidPaper:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(TandemColor.paper)
        case .glass:
            glassShape
        }
    }

    @ViewBuilder
    private var glassShape: some View {
        if #available(macOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

public extension View {
    /// Applies the shared glass/solid-paper background described above at the given corner
    /// radius (see ``TandemRadius``).
    func glassSurface(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}
