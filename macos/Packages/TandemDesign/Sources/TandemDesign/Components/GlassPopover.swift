import SwiftUI

/// The menu bar extra popover content (ui-spec §5.1, §7.1): 340 pt wide, 20 pt padding, on the
/// shared glass surface.
public struct GlassPopover<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(TandemSpacing.popoverPadding)
            .frame(width: 340)
            .glassSurface(cornerRadius: TandemRadius.popoverWindow)
            .tandemPopoverChrome()
    }
}

#Preview {
    GlassPopover {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Pixel 9.", state: "Connected.")
            NumberedActionRow(index: 1, title: "Send file") {}
            NumberedActionRow(index: 2, title: "Push clipboard") {}
        }
    }
}
