import SwiftUI

/// A small grid of dots showing a fraction (ui-spec §2 "dot motif", the popover's battery gauge):
/// lit = `ink`, unlit = `ink` at 12%, the last lit dot (the current position) = `signal`. Dots
/// light from the bottom row up, left to right. Exposes a VoiceOver value ("82%") since the dots
/// themselves are decorative.
public struct DotMatrix: View {
    private let value: Double
    private let columns: Int
    private let rows: Int

    @Environment(\.colorSchemeContrast) private var contrast

    public nonisolated init(value: Double, columns: Int = 10, rows: Int = 3) {
        self.value = value.clamped(to: 0...1)
        self.columns = columns
        self.rows = rows
    }

    nonisolated var litCount: Int {
        Int((Double(columns * rows) * value).rounded())
    }

    nonisolated func dotState(row: Int, column: Int) -> DotProgress.DotState {
        let order = (rows - 1 - row) * columns + column
        guard order < litCount else { return .unlit }
        return order == litCount - 1 ? .current : .lit
    }

    public var body: some View {
        VStack(spacing: TandemSpacing.extraSmall) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: TandemSpacing.extraSmall) {
                    ForEach(0..<columns, id: \.self) { column in
                        Circle()
                            .fill(color(for: dotState(row: row, column: column)))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityValue(DotProgress.accessibilityValueText(value: value))
    }

    private func color(for state: DotProgress.DotState) -> Color {
        switch state {
        case .unlit: TandemColor.lineUnlit(increasedContrast: contrast == .increased)
        case .lit: TandemColor.ink
        case .current: TandemColor.signal
        }
    }
}

#Preview {
    DotMatrix(value: 0.82)
        .padding()
}
