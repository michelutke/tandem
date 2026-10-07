import SwiftUI

/// Renders a QR code (ui-spec §5.1, §9.2) as dots instead of squares, keeping it scannable: the
/// three finder patterns are drawn as solid rounded rings (a scanner locates the code by their 1:1:3:1:1
/// ratio), every other module is a dot, and the quiet zone is >= 4 modules (verified further by
/// E14-11). Takes a pre-computed module grid; QR encoding itself is out of scope here.
public struct DotQR: View {
    /// `modules[row][col]` is `true` for a dark module. Must be square.
    private let modules: [[Bool]]

    public nonisolated static let quietZoneModules = 4

    /// Data-dot diameter as a fraction of one module; large enough to stay robust under camera blur.
    nonisolated static let dataDotDiameter: CGFloat = 0.85

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

    /// Module-grid (row, col) origins of the three 7x7 finder patterns, in the quiet-zone-less grid.
    nonisolated static func finderOrigins(size: Int) -> [(row: Int, col: Int)] {
        [(0, 0), (0, size - 7), (size - 7, 0)]
    }

    /// One finder pattern as solid shapes: a 7x7 ring (even-odd fill with a 5x5 hole) plus a 3x3
    /// centre, so a detector sees an unbroken 1:1:3:1:1 run in every direction.
    nonisolated static func finderPath(origin: (row: Int, col: Int), moduleSize: CGFloat) -> Path {
        func rect(inset: CGFloat, modules: CGFloat) -> CGRect {
            CGRect(
                x: (CGFloat(origin.col + quietZoneModules) + inset) * moduleSize,
                y: (CGFloat(origin.row + quietZoneModules) + inset) * moduleSize,
                width: modules * moduleSize,
                height: modules * moduleSize
            )
        }
        func corner(_ modules: CGFloat) -> CGSize {
            CGSize(width: moduleSize * modules, height: moduleSize * modules)
        }
        var path = Path()
        path.addRoundedRect(in: rect(inset: 0, modules: 7), cornerSize: corner(1.2))
        path.addRoundedRect(in: rect(inset: 1, modules: 5), cornerSize: corner(0.6))
        path.addRoundedRect(in: rect(inset: 2, modules: 3), cornerSize: corner(0.6))
        return path
    }

    public var body: some View {
        let size = modules.count
        let totalModules = size + Self.quietZoneModules * 2
        Canvas { context, canvasSize in
            guard size > 0 else { return }
            let moduleSize = min(canvasSize.width, canvasSize.height) / CGFloat(totalModules)
            for origin in Self.finderOrigins(size: size) {
                context.fill(
                    Self.finderPath(origin: origin, moduleSize: moduleSize),
                    with: .color(TandemColor.ink),
                    style: FillStyle(eoFill: true)
                )
            }
            let inset = (1 - Self.dataDotDiameter) / 2
            for row in 0..<size {
                for col in 0..<size where modules[row][col] {
                    guard !Self.isFinderPatternModule(row: row, col: col, size: size) else { continue }
                    let origin = CGPoint(
                        x: (CGFloat(col + Self.quietZoneModules) + inset) * moduleSize,
                        y: (CGFloat(row + Self.quietZoneModules) + inset) * moduleSize
                    )
                    let diameter = moduleSize * Self.dataDotDiameter
                    let rect = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
                    context.fill(Path(ellipseIn: rect), with: .color(TandemColor.ink))
                }
            }
        }
        // A Canvas has no intrinsic size; hosts that size to the SwiftUI ideal size (NSHostingController's
        // default) would otherwise collapse the QR to zero height.
        .frame(minWidth: 200, idealWidth: 280, minHeight: 200, idealHeight: 280)
        .aspectRatio(1, contentMode: .fit)
        // Always dark-on-white, whatever surface hosts it (glass windows are grey): scanners need contrast.
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TandemColor.paper))
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
