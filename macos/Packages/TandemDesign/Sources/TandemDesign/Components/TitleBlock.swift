import SwiftUI

/// The "title pair" pattern (ui-spec §2): line 1 is the subject, bold; line 2 is the state,
/// regular and grey (red for a trust failure, ink when the state is the screen's live activity).
/// Both lines share one size. Read by accessibility as a single heading (ui-spec §11: "Pixel 9,
/// connected").
public struct TitleBlock: View {
    private let subject: String
    private let state: String
    private let isAlert: Bool
    private let emphasizesState: Bool
    private let size: CGFloat

    public init(
        subject: String,
        state: String,
        isAlert: Bool = false,
        emphasizesState: Bool = false,
        size: CGFloat = 24
    ) {
        self.subject = subject
        self.state = state
        self.isAlert = isAlert
        self.emphasizesState = emphasizesState
        self.size = size
    }

    private var stateColor: Color {
        if isAlert { return TandemColor.alert }
        return emphasizesState ? TandemColor.ink : TandemColor.ink2
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject)
                .tandemTextStyle(TandemTypography.titlePairBold(size: size))
                .foregroundStyle(TandemColor.ink)
            Text(state)
                .tandemTextStyle(TandemTypography.titlePairRegular(size: size))
                .foregroundStyle(stateColor)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Connected") {
    TitleBlock(subject: "Pixel 9.", state: "Connected.")
        .padding()
}

#Preview("Key changed") {
    TitleBlock(subject: "Key changed.", state: "Pair again to keep using Pixel 9.", isAlert: true)
        .padding()
}
