import Foundation
@testable import TandemProtocol

/// `display-strings` category handler for ``ConformanceRunner`` (E15-02): reuses
/// `DisplayStringVectorFixture` directly since it already lives in this same test target.
extension ConformanceRunner {
    static func runDisplayStrings(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(DisplayStringVectorFixture.Manifest.self, from: data)
        return try manifest.vectors.map { entry in
            guard let kind = DisplayStringSanitizer.Kind(rawValue: entry.input.kind) else {
                throw ConformanceFailure(description: "vector \(entry.id) has unknown kind \(entry.input.kind)")
            }
            let rawBytes = try DisplayStringVectorFixture.rawBytes(for: entry)
            let actual = DisplayStringSanitizer.sanitize(rawBytes, kind: kind)
            let passed = actual == entry.expected.sanitized
            return VectorOutcome(
                id: entry.id, category: "display-strings", outcome: passed ? "pass" : "fail",
                expected: entry.expected.sanitized, actual: actual
            )
        }
    }
}
