import SwiftUI

/// Content background for a glass window (ui-spec §5.1): used for pairing and Settings. Fills the
/// whole window under a transparent title bar; traffic lights are the host `NSWindow`'s own.
public struct GlassWindow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(TandemSpacing.windowPadding)
            .padding(.top, TandemSpacing.large)
            .glassSurface(cornerRadius: 0)
            .ignoresSafeArea()
            .tandemWindowChrome()
    }
}

#Preview {
    GlassWindow {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Pixel 9.", state: "Same code on both?")
            Text("482 913")
                .tandemTextStyle(TandemTypography.displayNumeral(size: 64))
                .foregroundStyle(TandemColor.ink)
        }
        .frame(width: 360)
    }
}
