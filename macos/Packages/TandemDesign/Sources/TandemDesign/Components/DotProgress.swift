import SwiftUI

/// A row of dots showing linear progress (ui-spec §2 "dot motif", §5.1): lit = `ink`, unlit =
/// `ink` at 12%, the current position (the last lit dot) = `signal` unless `leadsWithSignal` is
/// off. Exposes a VoiceOver value ("43%") since the dots themselves are decorative.
public struct DotProgress: View {
    private let value: Double
    private let dotCount: Int
    private let leadsWithSignal: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    public nonisolated init(value: Double, dotCount: Int = 10, leadsWithSignal: Bool = true) {
        self.value = value.clamped(to: 0...1)
        self.dotCount = dotCount
        self.leadsWithSignal = leadsWithSignal
    }

    /// The VoiceOver value text for a given progress fraction (0...1), e.g. `0.43` -> `"43%"`.
    public nonisolated static func accessibilityValueText(value: Double) -> String {
        "\(Int((value.clamped(to: 0...1) * 100).rounded()))%"
    }

    nonisolated var litCount: Int {
        Int((Double(dotCount) * value).rounded())
    }

    enum DotState: Equatable {
        case unlit
        case lit
        case current
    }

    nonisolated func dotState(at index: Int) -> DotState {
        guard index < litCount else { return .unlit }
        return leadsWithSignal && index == litCount - 1 ? .current : .lit
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
        switch dotState(at: index) {
        case .unlit: TandemColor.lineUnlit(increasedContrast: contrast == .increased)
        case .lit: TandemColor.ink
        case .current: TandemColor.signal
        }
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
