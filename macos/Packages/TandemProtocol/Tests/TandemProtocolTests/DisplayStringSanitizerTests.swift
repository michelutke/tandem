import Foundation
import Testing
@testable import TandemProtocol

/// E14-22: Swift `DisplayStringSanitizer`, the macOS counterpart to Android's
/// `DisplayStringSanitizer` (E14-21), both implementing SPEC.md's untrusted-peer-string
/// sanitization rule (E01-23) and validated against the shared E01-24 vector suite.
struct DisplayStringSanitizerTests {
    @Test
    func macDisplaySanitizer_everyDisplayStringVector_matchesExpected() throws {
        let manifest = try DisplayStringVectorFixture.load()
        #expect(!manifest.vectors.isEmpty)

        for vector in manifest.vectors {
            guard let kind = DisplayStringSanitizer.Kind(rawValue: vector.input.kind) else {
                Issue.record("vector \(vector.id) has unknown kind \(vector.input.kind)")
                continue
            }
            let rawBytes = try DisplayStringVectorFixture.rawBytes(for: vector)
            let sanitized = DisplayStringSanitizer.sanitize(rawBytes, kind: kind)
            #expect(sanitized == vector.expected.sanitized, "vector \(vector.id)")
        }
    }

    @Test
    func macDisplaySanitizer_randomNameInput_neverContainsBidiOrControlChars() {
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<10_000 {
            let length = Int.random(in: 0...256, using: &generator)
            let bytes = Data((0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
            let sanitized = DisplayStringSanitizer.sanitize(bytes, kind: .name)

            for scalar in sanitized.unicodeScalars {
                #expect(!Self.bidiControls.contains(scalar.value))
                #expect(!Self.isC0OrC1(scalar.value))
                #expect(!Self.zeroWidth.contains(scalar.value))
            }
            // 64 kept graphemes plus, at most, one distinct appended-ellipsis grapheme
            // (SPEC.md step 7): the ellipsis does not count against the 64-scalar-value cap.
            #expect(sanitized.count <= 65)
        }
    }

    private static let bidiControls: Set<UInt32> = [
        0x200E, 0x200F, 0x061C,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069
    ]

    private static let zeroWidth: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]

    private static func isC0OrC1(_ value: UInt32) -> Bool {
        (0x00...0x1F).contains(value) || (0x7F...0x9F).contains(value)
    }
}
