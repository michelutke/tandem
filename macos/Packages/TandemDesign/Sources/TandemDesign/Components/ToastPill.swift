import SwiftUI

/// A compact glass pill with a signal dot and one line of text (ui-spec §5.1 `ToastPill`).
public struct ToastPill: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: TandemSpacing.small) {
            Circle()
                .fill(TandemColor.signal)
                .frame(width: 8, height: 8)
            Text(text)
                .tandemTextStyle(TandemTypography.rowTitle(size: 14))
                .foregroundStyle(TandemColor.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, TandemSpacing.large)
        .padding(.vertical, TandemSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: TandemRadius.sheet, style: .continuous)
                .fill(TandemColor.paper.opacity(0.85))
        )
        .glassSurface(cornerRadius: TandemRadius.sheet)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ToastPill("Copied from Pixel 9.")
        .padding()
}
