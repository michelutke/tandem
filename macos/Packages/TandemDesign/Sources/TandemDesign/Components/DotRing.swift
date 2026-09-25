import SwiftUI

/// A ring of dots showing progress around a circle (ui-spec §2 "dot motif", §6 home ring): lit
/// dots go clockwise from 12 o'clock, the current position is `signal`, unlit dots are `ink` at
/// 12%. Exposes a VoiceOver value ("43%") since the ring itself is decorative.
public struct DotRing: View {
    private let value: Double
    private let dotCount: Int
    private let dotSize: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    public nonisolated init(value: Double, dotCount: Int = 24, dotSize: CGFloat = 4) {
        self.value = value.clamped(to: 0...1)
        self.dotCount = dotCount
        self.dotSize = dotSize
    }

    /// The VoiceOver value text for a given ring fraction (0...1), e.g. `0.43` -> `"43%"`.
    public nonisolated static func accessibilityValueText(value: Double) -> String {
        DotProgress.accessibilityValueText(value: value)
    }

    nonisolated var litCount: Int {
        Int((Double(dotCount) * value).rounded())
    }

    public var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2 - dotSize
            ZStack {
                ForEach(0..<dotCount, id: \.self) { index in
                    let angle = Angle.degrees(360 / Double(dotCount) * Double(index) - 90)
                    Circle()
                        .fill(dotColor(at: index))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement()
        .accessibilityValue(Self.accessibilityValueText(value: value))
    }

    private func dotColor(at index: Int) -> Color {
        guard index < litCount else {
            return TandemColor.lineUnlit(increasedContrast: contrast == .increased)
        }
        return index == litCount - 1 ? TandemColor.signal : TandemColor.ink
    }
}

#Preview {
    DotRing(value: 0.43)
        .frame(width: 120, height: 120)
        .padding()
}
