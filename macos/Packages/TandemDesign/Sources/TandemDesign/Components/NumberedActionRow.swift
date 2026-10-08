import SwiftUI

/// A numbered action row ("01 Send file") (ui-spec §2, §5.1): grey mono index, row-title label,
/// optional trailing meta ("default"), ink-5% background on hover.
public struct NumberedActionRow: View {
    private let index: Int
    private let title: String
    private let trailingMeta: String?
    private let identifier: String?
    private let isSelected: Bool
    private let emphasizesSelection: Bool
    private let verticalPadding: CGFloat
    private let horizontalPadding: CGFloat
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        index: Int,
        title: String,
        trailingMeta: String? = nil,
        identifier: String? = nil,
        isSelected: Bool = false,
        emphasizesSelection: Bool = false,
        verticalPadding: CGFloat = TandemSpacing.rowVertical,
        horizontalPadding: CGFloat = TandemSpacing.popoverPadding,
        action: @escaping () -> Void
    ) {
        self.index = index
        self.title = title
        self.trailingMeta = trailingMeta
        self.identifier = identifier
        self.isSelected = isSelected
        self.emphasizesSelection = emphasizesSelection
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    private var unselectedStyle: TandemTextStyle { TandemTypography.body(size: 16) }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TandemSpacing.small) {
                Text(String(format: "%02d", index))
                    .tandemTextStyle(TandemTypography.metaMono())
                    .foregroundStyle(TandemColor.ink2)
                Text(title)
                    .tandemTextStyle(isSelected || !emphasizesSelection ? TandemTypography.rowTitle() : unselectedStyle)
                    .foregroundStyle(TandemColor.ink)
                Spacer()
                if let trailingMeta {
                    Text(trailingMeta)
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                }
            }
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: TandemRadius.row, style: .continuous)
                    .fill(isHovering || isSelected ? TandemColor.ink.opacity(0.05) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? title)
    }
}

#Preview {
    VStack(spacing: 0) {
        NumberedActionRow(index: 1, title: "Send file") {}
        NumberedActionRow(index: 2, title: "Push clipboard") {}
        NumberedActionRow(index: 3, title: "Don't pair", trailingMeta: "default") {}
    }
    .frame(width: 300)
}
