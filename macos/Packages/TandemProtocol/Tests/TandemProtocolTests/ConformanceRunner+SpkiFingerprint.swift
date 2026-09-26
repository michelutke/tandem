import Foundation
import TandemCrypto

/// `spki-fingerprint` category handler for ``ConformanceRunner`` (E15-02). Duplicates a small
/// manifest-entry shape rather than reusing `TandemCryptoTests`' own `SpkiFingerprintVectorFixture`,
/// since one Swift test target cannot import another package's test target (mirrors the existing
/// duplication between, e.g., `SpkiFingerprintVectorFixture` and `PairingProofVectorFixture`).
extension ConformanceRunner {
    struct SpkiInput: Decodable { let spkiDerHex: String }
    struct SpkiExpected: Decodable { let fingerprintHex: String }
    struct SpkiVectorEntry: Decodable {
        let id: String
        let input: SpkiInput
        let expected: SpkiExpected?
        let expectedError: String?
    }
    struct SpkiManifest: Decodable { let vectors: [SpkiVectorEntry] }

    static func runSpkiFingerprint(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(SpkiManifest.self, from: data)
        return try manifest.vectors.map { entry in
            let spkiDer = try conformanceRunnerHexDecode(entry.input.spkiDerHex)
            if let expected = entry.expected {
                return try spkiFingerprintValidOutcome(entry.id, spkiDer, expected)
            }
            return spkiFingerprintInvalidOutcome(entry.id, spkiDer, entry.expectedError ?? "unknown")
        }
    }

    private static func spkiFingerprintValidOutcome(
        _ id: String, _ spkiDer: Data, _ expected: SpkiExpected
    ) throws -> VectorOutcome {
        let actualHex: String
        do {
            actualHex = try SpkiFingerprint.compute(spkiDer: spkiDer).conformanceRunnerHex
        } catch {
            return VectorOutcome(
                id: id, category: "spki-fingerprint", outcome: "fail",
                expected: expected.fingerprintHex, actual: "threw \(error)"
            )
        }
        let passed = actualHex == expected.fingerprintHex
        return VectorOutcome(
            id: id, category: "spki-fingerprint", outcome: passed ? "pass" : "fail",
            expected: expected.fingerprintHex, actual: actualHex
        )
    }

    private static func spkiFingerprintInvalidOutcome(
        _ id: String, _ spkiDer: Data, _ expectedError: String
    ) -> VectorOutcome {
        var actualError = "no error thrown"
        do {
            _ = try SpkiFingerprint.compute(spkiDer: spkiDer)
        } catch let error as SpkiFingerprint.ValidationError {
            actualError = spkiErrorName(error)
        } catch {
            actualError = "threw \(error)"
        }
        let passed = actualError == expectedError
        return VectorOutcome(
            id: id, category: "spki-fingerprint", outcome: passed ? "pass" : "fail",
            expected: expectedError, actual: actualError
        )
    }

    private static func spkiErrorName(_ error: SpkiFingerprint.ValidationError) -> String {
        switch error {
        case .unsupportedPointEncoding: return "unsupportedPointEncoding"
        case .unsupportedKeyType: return "unsupportedKeyType"
        case .malformedSpki: return "malformedSpki"
        case .invalidByteCount: return "invalidByteCount"
        }
    }
}
