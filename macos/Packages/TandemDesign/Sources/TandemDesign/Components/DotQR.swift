import SwiftUI

/// Renders a QR code (ui-spec §5.1, §9.2) as dots instead of squares, keeping it scannable: the
/// three finder patterns stay rounded squares (a scanner locates the code by their 1:1:3:1:1
/// ratio), every other module is a dot, and the quiet zone is >= 4 modules (verified further by
/// E14-11). Takes a pre-computed module grid; QR encoding itself is out of scope here.
public struct DotQR: View {
    /// `modules[row][col]` is `true` for a dark module. Must be square.
    private let modules: [[Bool]]

    public nonisolated static let quietZoneModules = 4

    public init(modules: [[Bool]]) {
        self.modules = modules
    }

    /// The three finder-pattern squares sit in the top-left, top-right and bottom-left 7x7
    /// corners of every QR symbol.
    nonisolated static func isFinderPatternModule(row: Int, col: Int, size: Int) -> Bool {
        let topLeft = row < 7 && col < 7
        let topRight = row < 7 && col >= size - 7
        let bottomLeft = row >= size - 7 && col < 7
        return topLeft || topRight || bottomLeft
    }

    public var body: some View {
        let size = modules.count
        let totalModules = size + Self.quietZoneModules * 2
        Canvas { context, canvasSize in
            guard size > 0 else { return }
            let moduleSize = min(canvasSize.width, canvasSize.height) / CGFloat(totalModules)
            for row in 0..<size {
                for col in 0..<size where modules[row][col] {
                    let origin = CGPoint(
                        x: (CGFloat(col + Self.quietZoneModules) + 0.15) * moduleSize,
                        y: (CGFloat(row + Self.quietZoneModules) + 0.15) * moduleSize
                    )
                    let rect = CGRect(origin: origin, size: CGSize(width: moduleSize * 0.7, height: moduleSize * 0.7))
                    let path = Self.isFinderPatternModule(row: row, col: col, size: size)
                        ? Path(roundedRect: rect, cornerRadius: moduleSize * 0.3)
                        : Path(ellipseIn: rect)
                    context.fill(path, with: .color(TandemColor.ink))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    DotQR(modules: DotQR.previewModules)
        .frame(width: 220, height: 220)
        .padding()
}

extension DotQR {
    /// A tiny synthetic grid (not a valid QR payload) for previews/tests only.
    static var previewModules: [[Bool]] {
        (0..<21).map { row in (0..<21).map { col in (row + col).isMultiple(of: 3) } }
    }
}
