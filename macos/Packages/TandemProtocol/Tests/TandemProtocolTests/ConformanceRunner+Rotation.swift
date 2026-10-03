import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `rotation-encoding` category handler for ``ConformanceRunner`` (E70-01): decodes the raw message
/// bytes each vector describes (`input.messageHex` -- see `protocol/vectors/README.md`) with the
/// real generated rotation message types (`protocol/proto/tandem/v1/rotation.proto`), selected by
/// `input.kind`; `keyRotation` vectors additionally verify both ECDSA signatures over the SPEC
/// #key-rotation transcript.
extension ConformanceRunner {
    private static let rotationCategory = "rotation-encoding"
    private static let rotationChallengeLength = 32
    private static let p256SpkiLength = 91
    private static let uncompressedPointTag: UInt8 = 0x04
    private static let p256SpkiHeader = Data([
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ])
    private static let rotateLabel = Data("tandem-rotate-v1".utf8)

    static func runRotationEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(RotationEncodingManifest.self, from: data)
        return try manifest.vectors.map(rotationEncodingOutcome)
    }

    private static func rotationEncodingOutcome(_ vector: RotationEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex)
        let reencoded: Data?
        switch vector.input.kind {
        case "rotationChallenge": reencoded = try? Tandem_V1_RotationChallenge(serializedBytes: bytes).serializedData()
        case "rotationAck": reencoded = try? Tandem_V1_RotationAck(serializedBytes: bytes).serializedData()
        case "rotationReject": reencoded = try? Tandem_V1_RotationReject(serializedBytes: bytes).serializedData()
        case "keyRotation": reencoded = try? Tandem_V1_KeyRotation(serializedBytes: bytes).serializedData()
        default:
            throw ConformanceFailure(description: "unsupported rotation-encoding kind: \(vector.input.kind)")
        }
        guard let reencoded else {
            return VectorOutcome(
                id: vector.id, category: rotationCategory, outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        switch vector.input.kind {
        case "rotationChallenge": return try rotationChallengeOutcome(vector, bytes: bytes, reencoded: reencoded)
        case "rotationReject": return try rotationRejectOutcome(vector, bytes: bytes, reencoded: reencoded)
        case "keyRotation": return try keyRotationOutcome(vector, bytes: bytes, reencoded: reencoded)
        default: return try rotationRoundTripOutcome(vector, bytes: bytes, reencoded: reencoded)
        }
    }

    private static func rotationSha256Hex(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func rotationRoundTripOutcome(
        _ vector: RotationEncodingManifest.Vector, bytes: Data, reencoded: Data
    ) throws -> VectorOutcome {
        guard let expectedSha = vector.expected?.messageSha256 else {
            throw ConformanceFailure(description: "rotation-encoding vector \(vector.id) missing expected fields")
        }
        let passed = reencoded == bytes && rotationSha256Hex(bytes) == expectedSha
        return VectorOutcome(
            id: vector.id, category: rotationCategory, outcome: passed ? "pass" : "fail",
            expected: "sha256=\(expectedSha)", actual: "sha256=\(rotationSha256Hex(bytes))"
        )
    }

    private static func rotationChallengeOutcome(
        _ vector: RotationEncodingManifest.Vector, bytes: Data, reencoded: Data
    ) throws -> VectorOutcome {
        guard let expectedHex = vector.expected?.challengeHex else {
            throw ConformanceFailure(description: "rotation-encoding vector \(vector.id) missing expected fields")
        }
        let decoded = try Tandem_V1_RotationChallenge(serializedBytes: bytes)
        let roundTrip = try rotationRoundTripOutcome(vector, bytes: bytes, reencoded: reencoded)
        let expectedChallenge = try conformanceRunnerHexDecode(expectedHex)
        let passed = roundTrip.outcome == "pass" && decoded.challenge.count == rotationChallengeLength
            && decoded.challenge == expectedChallenge
        return VectorOutcome(
            id: vector.id, category: rotationCategory, outcome: passed ? "pass" : "fail",
            expected: "challengeLength=\(expectedChallenge.count)", actual: "challengeLength=\(decoded.challenge.count)"
        )
    }

    private static func rotationRejectOutcome(
        _ vector: RotationEncodingManifest.Vector, bytes: Data, reencoded: Data
    ) throws -> VectorOutcome {
        guard let expectedReason = vector.expected?.reason else {
            throw ConformanceFailure(description: "rotation-encoding vector \(vector.id) missing expected fields")
        }
        let decoded = try Tandem_V1_RotationReject(serializedBytes: bytes)
        let actualReason = "\(decoded.reason)"
        let roundTrip = try rotationRoundTripOutcome(vector, bytes: bytes, reencoded: reencoded)
        let names = [
            "INVALID_SIGNATURE": Tandem_V1_RotationRejectReason.invalidSignature,
            "UNAUTHENTICATED_SESSION": .unauthenticatedSession,
            "NOT_PRIMARY_PIN": .notPrimaryPin,
            "DUPLICATE_KEY": .duplicateKey,
            "ROTATION_UNAVAILABLE": .rotationUnavailable
        ]
        let passed = roundTrip.outcome == "pass" && names[expectedReason] == decoded.reason
        return VectorOutcome(
            id: vector.id, category: rotationCategory, outcome: passed ? "pass" : "fail",
            expected: "reason=\(expectedReason)", actual: "reason=\(actualReason)"
        )
    }

    private static func keyRotationOutcome(
        _ vector: RotationEncodingManifest.Vector, bytes: Data, reencoded: Data
    ) throws -> VectorOutcome {
        let decoded = try Tandem_V1_KeyRotation(serializedBytes: bytes)
        let oldSpkiDer = try conformanceRunnerHexDecode(vector.input.oldSpkiDerHex ?? "")
        let channelBinding = try conformanceRunnerHexDecode(vector.input.cbHex ?? "")
        let transcript = rotationTranscript(old: oldSpkiDer, new: decoded.newSpkiDer, channelBinding: channelBinding)
        let verified = isStrictP256Spki(decoded.newSpkiDer)
            && verifyEcdsa(spkiDer: oldSpkiDer, message: transcript, signatureDer: decoded.sigOldKey)
            && verifyEcdsa(spkiDer: decoded.newSpkiDer, message: transcript, signatureDer: decoded.sigNewKey)
        if vector.expected != nil {
            let roundTrip = try rotationRoundTripOutcome(vector, bytes: bytes, reencoded: reencoded)
            return VectorOutcome(
                id: vector.id, category: rotationCategory,
                outcome: verified && roundTrip.outcome == "pass" ? "pass" : "fail",
                expected: "valid=true", actual: "valid=\(verified)"
            )
        }
        guard let expectedError = vector.expectedError else {
            throw ConformanceFailure(description: "vector \(vector.id) has neither expected nor expectedError")
        }
        let actual = verified ? "valid" : "invalidSignature"
        return VectorOutcome(
            id: vector.id, category: rotationCategory, outcome: actual == expectedError ? "pass" : "fail",
            expected: expectedError, actual: actual
        )
    }

    private static func isStrictP256Spki(_ spkiDer: Data) -> Bool {
        spkiDer.count == p256SpkiLength
            && spkiDer.prefix(p256SpkiHeader.count) == p256SpkiHeader
            && spkiDer[spkiDer.startIndex + p256SpkiHeader.count] == uncompressedPointTag
    }

    private static func rotationTranscript(old: Data, new: Data, channelBinding: Data) -> Data {
        var transcript = rotateLabel
        for part in [old, new, channelBinding] {
            transcript.append(UInt8(part.count >> 8))
            transcript.append(UInt8(part.count & 0xFF))
            transcript.append(part)
        }
        return transcript
    }

    private static func verifyEcdsa(spkiDer: Data, message: Data, signatureDer: Data) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(derRepresentation: spkiDer),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureDer) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: message)
    }
}

struct RotationEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String
        let oldSpkiDerHex: String?
        let cbHex: String?
    }
    struct Expected: Decodable {
        let challengeHex: String?
        let reason: String?
        let messageSha256: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
