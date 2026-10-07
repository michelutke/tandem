import SwiftUI

/// A 1 px `line` separator (ui-spec §2: hairline between rows), honouring Increase Contrast.
public struct Hairline: View {
    @Environment(\.colorSchemeContrast) private var contrast

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(TandemColor.line(increasedContrast: contrast == .increased))
            .frame(height: 1)
    }
}
