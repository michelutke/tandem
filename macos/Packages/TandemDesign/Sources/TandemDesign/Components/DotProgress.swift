import SwiftUI

/// A row of dots showing linear progress (ui-spec §2 "dot motif", §5.1): lit = `ink`, unlit =
/// `ink` at 12%. Exposes a VoiceOver value ("43%") since the dots themselves are decorative.
public struct DotProgress: View {
    private let value: Double
    private let dotCount: Int

    @Environment(\.colorSchemeContrast) private var contrast

    public nonisolated init(value: Double, dotCount: Int = 10) {
        self.value = value.clamped(to: 0...1)
        self.dotCount = dotCount
    }

    /// The VoiceOver value text for a given progress fraction (0...1), e.g. `0.43` -> `"43%"`.
    public nonisolated static func accessibilityValueText(value: Double) -> String {
        "\(Int((value.clamped(to: 0...1) * 100).rounded()))%"
    }

    nonisolated var litCount: Int {
        Int((Double(dotCount) * value).rounded())
    }

    public var body: some View {
        HStack(spacing: TandemSpacing.extraSmall) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(dotColor(at: index))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityValue(Self.accessibilityValueText(value: value))
    }

    private func dotColor(at index: Int) -> Color {
        index < litCount ? TandemColor.ink : TandemColor.lineUnlit(increasedContrast: contrast == .increased)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    DotProgress(value: 0.43)
        .padding()
}
