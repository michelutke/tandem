import SwiftUI

/// A glass card for a mirrored notification shown without system notification permission: app
/// name, title and body (ui-spec §5.1 `ToastPill`'s larger sibling). Click dismisses.
public struct NotificationBannerCard: View {
    public static let width: CGFloat = 340

    private let appName: String
    private let title: String
    private let message: String
    private let onDismiss: () -> Void

    public init(appName: String, title: String, message: String, onDismiss: @escaping () -> Void) {
        self.appName = appName
        self.title = title
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            HStack(spacing: TandemSpacing.small) {
                Circle()
                    .fill(TandemColor.signal)
                    .frame(width: 8, height: 8)
                Text(appName)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(1)
            }
            if !title.isEmpty {
                Text(title)
                    .tandemTextStyle(TandemTypography.rowTitle(size: 14))
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(1)
            }
            if !message.isEmpty {
                Text(message)
                    .tandemTextStyle(TandemTypography.body())
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(3)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .padding(TandemSpacing.large)
        .background(
            RoundedRectangle(cornerRadius: TandemRadius.sheet, style: .continuous)
                .fill(TandemColor.paper.opacity(0.85))
        )
        .glassSurface(cornerRadius: TandemRadius.sheet)
        .environment(\.colorScheme, .light)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NotificationBannerCard(appName: "com.example.chat", title: "Ada", message: "Lunch at 12?", onDismiss: {})
        .padding()
}
