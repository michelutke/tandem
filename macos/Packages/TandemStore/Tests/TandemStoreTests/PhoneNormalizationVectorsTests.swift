import Foundation
import Testing
@testable import TandemStore

/// Runs `protocol/vectors/phone-normalization.json` (E51-06) through the production
/// ``PhoneNumberNormalizer``; Android's `PhoneNormalizationVectorsTest` runs the same file through
/// libphonenumber.
private struct PhoneVectorManifest: Decodable {
    let vectors: [PhoneVector]
}

private struct PhoneVectorInput: Decodable {
    let raw: String
    let region: String
}

private struct PhoneVectorExpected: Decodable {
    let e164: String?
}

private struct PhoneVector: Decodable {
    let id: String
    let input: PhoneVectorInput
    let expected: PhoneVectorExpected
}

struct PhoneNormalizationVectorsTests {
    @Test
    func phoneNormalizationVectors_validCases_identicalE164BothPlatforms() throws {
        let valid = try loadVectors().filter { $0.expected.e164 != nil }

        #expect(!valid.isEmpty)
        for vector in valid {
            let actual = PhoneNumberNormalizer(defaultRegion: vector.input.region).normalizedE164(of: vector.input.raw)
            #expect(actual == vector.expected.e164, "\(vector.id)")
        }
    }

    @Test
    func phoneNormalizationVectors_invalidCases_nullE164BothPlatforms() throws {
        let invalid = try loadVectors().filter { $0.expected.e164 == nil }

        #expect(!invalid.isEmpty)
        for vector in invalid {
            let actual = PhoneNumberNormalizer(defaultRegion: vector.input.region).normalizedE164(of: vector.input.raw)
            #expect(actual == nil, "\(vector.id): got \(actual ?? "nil")")
        }
    }

    private func loadVectors() throws -> [PhoneVector] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "protocol/vectors/phone-normalization.json")
        return try JSONDecoder().decode(PhoneVectorManifest.self, from: Data(contentsOf: url)).vectors
    }
}
