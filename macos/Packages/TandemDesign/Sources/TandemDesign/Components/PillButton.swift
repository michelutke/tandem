import SwiftUI

/// Which fill a ``PillButton`` uses (ui-spec §2, §5.1): "at most one filled button per screen;
/// secondary actions are outlined or plain rows... destructive = red fill." `destructiveSoft` is
/// the resting form of a destructive action on a screen that already has its one filled button
/// (alert-tinted fill, alert text); the confirmation sheet then uses `destructive`.
public enum PillButtonKind: Equatable, Sendable {
    case primary
    case destructive
    case destructiveSoft
    case secondary

    var background: Color {
        switch self {
        case .primary: TandemColor.ink
        case .destructive: TandemColor.alert
        case .destructiveSoft: TandemColor.alert.opacity(0.1)
        case .secondary: TandemColor.ink.opacity(0.05)
        }
    }

    var foreground: Color {
        switch self {
        case .primary, .destructive: TandemColor.paper
        case .destructiveSoft: TandemColor.alert
        case .secondary: TandemColor.ink
        }
    }
}

/// A full-pill button (ui-spec §3.3: "glass buttons full pill"). Primary/destructive are filled;
/// secondary is an `ink` 5% fill.
public struct PillButton: View {
    private let title: String
    private let kind: PillButtonKind
    private let action: () -> Void

    public init(_ title: String, kind: PillButtonKind = .primary, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .tandemTextStyle(TandemTypography.rowTitle())
                .frame(maxWidth: .infinity)
                .padding(.vertical, TandemSpacing.small + TandemSpacing.extraSmall)
        }
        .buttonStyle(.plain)
        .foregroundStyle(kind.foreground)
        .background(Capsule().fill(kind.background))
    }
}

#Preview {
    VStack(spacing: TandemSpacing.small) {
        PillButton("Pair") {}
        PillButton("Don't pair", kind: .secondary) {}
        PillButton("Revoke", kind: .destructive) {}
    }
    .padding()
    .frame(width: 260)
}
