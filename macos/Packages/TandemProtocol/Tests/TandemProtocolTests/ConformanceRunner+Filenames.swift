import TandemProtocol
import Foundation

private struct FilenamesVectorInput: Decodable {
    let rawUtf8Hex: String
    let transferId: String
}

private struct FilenamesVectorExpected: Decodable {
    let filename: String
}

private struct FilenamesVector: Decodable {
    let id: String
    let input: FilenamesVectorInput
    let expected: FilenamesVectorExpected?
    let expectedError: String?
}

private struct FilenamesManifest: Decodable {
    let vectors: [FilenamesVector]
}

/// `filenames` category handler for ``ConformanceRunner`` (E40-02): applies the production
/// ``FilenameSanitizer`` (E40-17, docs/protocol/SPEC.md `#filename-sanitization`) to each vector's raw name.
extension ConformanceRunner {
    static let invalidNameError = "invalidName"

    static func runFilenames(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(FilenamesManifest.self, from: data)
        return try manifest.vectors.map { vector in
            let raw = try conformanceRunnerHexDecode(vector.input.rawUtf8Hex)
            guard let name = String(data: raw, encoding: .utf8) else {
                throw ConformanceFailure(description: "filenames vector \(vector.id) is not valid UTF-8")
            }
            let expected = vector.expectedError ?? vector.expected?.filename ?? ""
            let actual = sanitizedOrError(name, transferId: vector.input.transferId)
            return VectorOutcome(
                id: vector.id, category: "filenames", outcome: actual == expected ? "pass" : "fail",
                expected: expected, actual: actual
            )
        }
    }

    private static func sanitizedOrError(_ name: String, transferId: String) -> String {
        do {
            return try FilenameSanitizer.sanitize(name, transferId: transferId)
        } catch FilenameSanitizerError.invalidName {
            return invalidNameError
        } catch {
            return "\(error)"
        }
    }
}
