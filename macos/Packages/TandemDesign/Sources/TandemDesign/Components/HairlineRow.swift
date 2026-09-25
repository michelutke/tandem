import SwiftUI

/// A key/value row separated by a 1 px hairline (ui-spec §2, §5.1): key (600 weight) on the
/// left, value (`ink2`, mono when it is a code) on the right. No boxes, ever.
public struct HairlineRow: View {
    private let key: String
    private let value: String
    private let valueIsMono: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    public init(key: String, value: String, valueIsMono: Bool = false) {
        self.key = key
        self.value = value
        self.valueIsMono = valueIsMono
    }

    public var body: some View {
        HStack {
            Text(key)
                .tandemTextStyle(TandemTypography.rowTitle())
                .foregroundStyle(TandemColor.ink)
            Spacer()
            Text(value)
                .tandemTextStyle(valueIsMono ? TandemTypography.metaMono() : TandemTypography.body())
                .foregroundStyle(TandemColor.ink2)
        }
        .padding(.vertical, TandemSpacing.rowVertical)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TandemColor.line(increasedContrast: contrast == .increased))
                .frame(height: 1)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        HairlineRow(key: "Paired", value: "12 Sep 2026")
        HairlineRow(key: "Phone key", value: "9F:2A:C1:0E", valueIsMono: true)
    }
    .padding()
}
