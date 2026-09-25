import SwiftUI

/// A modal confirmation on a 20% scrim (ui-spec §5.1), e.g. "Revoke Pixel 9?". The content itself
/// sits on a glass surface (``glassSurface(cornerRadius:)``).
public struct GlassSheet<Content: View>: View {
    private let isPresented: Bool
    private let content: Content

    public init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    public var body: some View {
        if isPresented {
            ZStack {
                TandemColor.ink.opacity(0.2)
                    .ignoresSafeArea()
                content
                    .padding(TandemSpacing.windowPadding)
                    .glassSurface(cornerRadius: TandemRadius.sheet)
            }
        }
    }
}

#Preview {
    GlassSheet(isPresented: true) {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Revoke Pixel 9?", state: "It will need to pair again.")
            PillButton("Revoke", kind: .destructive) {}
            PillButton("Cancel", kind: .secondary) {}
        }
        .frame(width: 280)
    }
}
