import Foundation
import Testing
@testable import TandemCrypto

@Test func pairingProof_everyHmacVector_matchesExpectedProof() throws {
    let manifest = try PairingProofVectorFixture.load()
    let proofEntries = manifest.vectors.filter { $0.input.kind == "proof" }
    #expect(!proofEntries.isEmpty)

    for entry in proofEntries {
        try assertProofVector(entry)
    }
}

/// A vector's decoded inputs, bundled so per-case assertions don't each re-decode every field.
private struct ProofVectorInputs {
    let secret: Data
    let macSpkiDer: Data
    let phoneSpkiDer: Data
    let channelBinding: Data

    init(_ entry: PairingProofVectorFixture.Entry) throws {
        secret = try PairingProofVectorFixture.secret(for: entry)
        macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
        phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
        channelBinding = try PairingProofVectorFixture.channelBinding(for: entry)
    }

    func verify(proof: Data) throws -> Bool {
        try PairingProof.verify(
            proof: proof,
            secret: secret,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: channelBinding
        )
    }
}

private func assertProofVector(_ entry: PairingProofVectorFixture.Entry) throws {
    let inputs = try ProofVectorInputs(entry)

    switch entry.expectedError {
    case nil:
        let proof = try PairingProofVectorFixture.proof(for: entry)
        let computed = try PairingProof.compute(
            secret: inputs.secret,
            macSpkiDer: inputs.macSpkiDer,
            phoneSpkiDer: inputs.phoneSpkiDer,
            channelBinding: inputs.channelBinding
        )
        #expect(computed == proof, "vector \(entry.id)")
        #expect(try inputs.verify(proof: proof), "vector \(entry.id)")
    case "proofMismatch":
        let proof = try PairingProofVectorFixture.proof(for: entry)
        #expect(try inputs.verify(proof: proof) == false, "vector \(entry.id)")
    case "malformedSpki":
        let proof = try PairingProofVectorFixture.proof(for: entry)
        #expect(throws: PairingProof.ValidationError.malformedSpki, "vector \(entry.id)") {
            _ = try inputs.verify(proof: proof)
        }
    case "malformedProof":
        let proof = try PairingProofVectorFixture.proof(for: entry)
        #expect(throws: PairingProof.ValidationError.malformedProof, "vector \(entry.id)") {
            _ = try inputs.verify(proof: proof)
        }
    default:
        Issue.record("vector \(entry.id) has unknown expectedError \(entry.expectedError ?? "nil")")
    }
}

@Test func pairingProof_secretOneBitFlipped_outputDiffers() throws {
    let manifest = try PairingProofVectorFixture.load()
    let entry = try #require(manifest.vectors.first { $0.input.kind == "proof" && $0.expectedError == nil })
    let secret = try PairingProofVectorFixture.secret(for: entry)
    let macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
    let phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
    let channelBinding = try PairingProofVectorFixture.channelBinding(for: entry)

    var flippedSecret = secret
    flippedSecret[0] ^= 0x01

    let original = try PairingProof.compute(
        secret: secret,
        macSpkiDer: macSpkiDer,
        phoneSpkiDer: phoneSpkiDer,
        channelBinding: channelBinding
    )
    let flipped = try PairingProof.compute(
        secret: flippedSecret,
        macSpkiDer: macSpkiDer,
        phoneSpkiDer: phoneSpkiDer,
        channelBinding: channelBinding
    )

    #expect(original != flipped)
}

@Test func pairingProof_macAndPhoneSpkiSwapped_outputDiffers() throws {
    let manifest = try PairingProofVectorFixture.load()
    let entry = try #require(manifest.vectors.first { $0.input.kind == "proof" && $0.expectedError == nil })
    let secret = try PairingProofVectorFixture.secret(for: entry)
    let macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
    let phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
    let channelBinding = try PairingProofVectorFixture.channelBinding(for: entry)

    let original = try PairingProof.compute(
        secret: secret,
        macSpkiDer: macSpkiDer,
        phoneSpkiDer: phoneSpkiDer,
        channelBinding: channelBinding
    )
    let swapped = try PairingProof.compute(
        secret: secret,
        macSpkiDer: phoneSpkiDer,
        phoneSpkiDer: macSpkiDer,
        channelBinding: channelBinding
    )

    #expect(original != swapped)
}

@Test func pairingCode_everyCodeVector_matchesExpectedSixDigits() throws {
    let manifest = try PairingProofVectorFixture.load()
    let codeEntries = manifest.vectors.filter { $0.input.kind == "code" }
    #expect(!codeEntries.isEmpty)

    for entry in codeEntries {
        guard let expectedCode = entry.expected?.code else {
            Issue.record("vector \(entry.id) missing expected.code")
            continue
        }
        let secret = try PairingProofVectorFixture.secret(for: entry)
        let macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
        let phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
        let channelBinding = try PairingProofVectorFixture.channelBinding(for: entry)

        let code = try ConfirmationCode.compute(
            secret: secret,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: channelBinding
        )

        #expect(code == expectedCode, "vector \(entry.id)")
        #expect(code.count == 6, "vector \(entry.id)")
    }
}

@Test func pairingProof_cbNot32Bytes_rejectedBeforeHmac() throws {
    let manifest = try PairingProofVectorFixture.load()
    let entry = try #require(manifest.vectors.first { $0.input.kind == "proof" && $0.expectedError == nil })
    let secret = try PairingProofVectorFixture.secret(for: entry)
    let macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
    let phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
    let shortChannelBinding = try PairingProofVectorFixture.channelBinding(for: entry).dropLast()

    #expect(throws: PairingProof.ValidationError.malformedChannelBinding) {
        _ = try PairingProof.compute(
            secret: secret,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: shortChannelBinding
        )
    }

    #expect(throws: ConfirmationCode.ValidationError.malformedChannelBinding) {
        _ = try ConfirmationCode.compute(
            secret: secret,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: shortChannelBinding
        )
    }
}
