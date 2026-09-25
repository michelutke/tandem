import SwiftUI

/// The system switch, tinted `ink` (ui-spec §5.1). No custom drawing: Liquid Glass toggles are a
/// system control, not something Tandem re-implements.
public struct GlassToggle: View {
    private let label: String
    private let isOn: Binding<Bool>

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self.isOn = isOn
    }

    public var body: some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.switch)
            .tint(TandemColor.ink)
    }
}

#Preview {
    @Previewable @State var isOn = true
    return GlassToggle("Auto-accept files", isOn: $isOn)
        .padding()
}
