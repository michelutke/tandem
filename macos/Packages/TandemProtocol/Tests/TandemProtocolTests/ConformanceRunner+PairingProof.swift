import Foundation
import TandemCrypto

/// `pairing-proof` category handler for ``ConformanceRunner`` (E15-02): covers both `proof`-kind
/// and `code`-kind manifest entries (SPEC.md #2). Duplicates a small manifest-entry shape rather
/// than reusing `TandemCryptoTests`' own `PairingProofVectorFixture` (see the note on
/// `ConformanceRunner+SpkiFingerprint.swift`).
extension ConformanceRunner {
    struct ProofInput: Decodable {
        let kind: String
        let secretHex: String
        let macSpkiDerHex: String
        let phoneSpkiDerHex: String
        let cbHex: String
        let proofHex: String?
    }
    struct ProofExpected: Decodable {
        let valid: Bool?
        let code: String?
    }
    struct ProofVectorEntry: Decodable {
        let id: String
        let input: ProofInput
        let expected: ProofExpected?
        let expectedError: String?
    }
    struct ProofManifest: Decodable { let vectors: [ProofVectorEntry] }

    /// `secret`/`macSpkiDer`/`phoneSpkiDer`/channel-binding bundled so the outcome functions below
    /// stay under SwiftLint's five-parameter limit.
    struct ProofInputs {
        let secret: Data
        let macSpkiDer: Data
        let phoneSpkiDer: Data
        let channelBinding: Data
    }

    static func runPairingProof(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(ProofManifest.self, from: data)
        return try manifest.vectors.map { try pairingProofOutcome($0) }
    }

    private static func pairingProofOutcome(_ entry: ProofVectorEntry) throws -> VectorOutcome {
        let inputs = ProofInputs(
            secret: try conformanceRunnerHexDecode(entry.input.secretHex),
            macSpkiDer: try conformanceRunnerHexDecode(entry.input.macSpkiDerHex),
            phoneSpkiDer: try conformanceRunnerHexDecode(entry.input.phoneSpkiDerHex),
            channelBinding: try conformanceRunnerHexDecode(entry.input.cbHex)
        )

        if entry.input.kind == "code" {
            return confirmationCodeOutcome(entry, inputs)
        }
        let proof = try conformanceRunnerHexDecode(entry.input.proofHex ?? "")
        if entry.expected != nil {
            return validProofOutcome(entry, proof, inputs)
        }
        return invalidProofOutcome(entry, proof, inputs)
    }

    private static func confirmationCodeOutcome(_ entry: ProofVectorEntry, _ inputs: ProofInputs) -> VectorOutcome {
        let expectedCode = entry.expected?.code ?? ""
        let actualCode: String
        do {
            actualCode = try ConfirmationCode.compute(
                secret: inputs.secret, macSpkiDer: inputs.macSpkiDer,
                phoneSpkiDer: inputs.phoneSpkiDer, channelBinding: inputs.channelBinding
            )
        } catch {
            actualCode = "threw \(error)"
        }
        let passed = actualCode == expectedCode
        return VectorOutcome(
            id: entry.id, category: "pairing-proof", outcome: passed ? "pass" : "fail",
            expected: expectedCode, actual: actualCode
        )
    }

    private static func validProofOutcome(
        _ entry: ProofVectorEntry, _ proof: Data, _ inputs: ProofInputs
    ) -> VectorOutcome {
        do {
            let valid = try PairingProof.verify(
                proof: proof, secret: inputs.secret, macSpkiDer: inputs.macSpkiDer,
                phoneSpkiDer: inputs.phoneSpkiDer, channelBinding: inputs.channelBinding
            )
            return VectorOutcome(
                id: entry.id, category: "pairing-proof", outcome: valid ? "pass" : "fail",
                expected: "valid=true", actual: "valid=\(valid)"
            )
        } catch {
            return VectorOutcome(
                id: entry.id, category: "pairing-proof", outcome: "fail",
                expected: "valid=true", actual: "threw \(error)"
            )
        }
    }

    private static func invalidProofOutcome(
        _ entry: ProofVectorEntry, _ proof: Data, _ inputs: ProofInputs
    ) -> VectorOutcome {
        let expectedError = entry.expectedError ?? "unknown"
        var actual: String
        do {
            let valid = try PairingProof.verify(
                proof: proof, secret: inputs.secret, macSpkiDer: inputs.macSpkiDer,
                phoneSpkiDer: inputs.phoneSpkiDer, channelBinding: inputs.channelBinding
            )
            actual = valid ? "valid" : "proofMismatch"
        } catch let error as PairingProof.ValidationError {
            actual = pairingProofErrorName(error)
        } catch {
            actual = "threw \(error)"
        }
        let passed = actual == expectedError
        return VectorOutcome(
            id: entry.id, category: "pairing-proof", outcome: passed ? "pass" : "fail",
            expected: expectedError, actual: actual
        )
    }

    private static func pairingProofErrorName(_ error: PairingProof.ValidationError) -> String {
        switch error {
        case .malformedSpki: return "malformedSpki"
        case .malformedChannelBinding: return "malformedChannelBinding"
        case .malformedProof: return "malformedProof"
        }
    }
}
