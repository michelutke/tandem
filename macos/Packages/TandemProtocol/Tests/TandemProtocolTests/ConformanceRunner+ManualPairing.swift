import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `manual-pairing` category handler for ``ConformanceRunner`` (E73-02): dispatches on `input.kind`
/// (`message`, `sas`, `commitment`, `sasCompare`, `sequence`) and compares the result with
/// `expectedError` or `expected`; see `protocol/vectors/README.md`.
extension ConformanceRunner {
    private static let manualCategory = "manual-pairing"
    private static let manualHashLength = 32
    private static let manualNonceLength = 16
    private static let sasModulus: UInt64 = 1_000_000
    private static let pairLabel = Data("tandem-manual-pair-v1".utf8)
    private static let commitLabel = Data("tandem-manual-commit-v1".utf8)
    private static let validSequence: [ManualPairingManifest.Message] = [
        .init(from: "phone", type: "commitment"),
        .init(from: "mac", type: "commitment"),
        .init(from: "phone", type: "reveal"),
        .init(from: "mac", type: "reveal"),
        .init(from: "mac", type: "manualPairResult")
    ]

    static func runManualPairing(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(ManualPairingManifest.self, from: data)
        return try manifest.vectors.map(manualPairingOutcome)
    }

    private static func manualPairingOutcome(_ vector: ManualPairingManifest.Vector) throws -> VectorOutcome {
        switch vector.input.kind {
        case "message": return try manualMessageOutcome(vector)
        case "sas": return try manualSasOutcome(vector)
        case "commitment": return manualVerdictOutcome(vector, try commitmentVerdict(vector.input))
        case "sasCompare": return try manualSasCompareOutcome(vector)
        case "sequence": return manualVerdictOutcome(vector, sequenceVerdict(vector.input.messages ?? []))
        default:
            return VectorOutcome(
                id: vector.id, category: manualCategory, outcome: "fail",
                expected: "known kind", actual: "unknown kind"
            )
        }
    }

    private static func manualVerdictOutcome(
        _ vector: ManualPairingManifest.Vector, _ verdict: String
    ) -> VectorOutcome {
        let expected = vector.expectedError ?? "accepted"
        return VectorOutcome(
            id: vector.id, category: manualCategory, outcome: verdict == expected ? "pass" : "fail",
            expected: expected, actual: verdict
        )
    }

    private static func manualMessageOutcome(_ vector: ManualPairingManifest.Vector) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex ?? "")
        guard let decoded = decodeManualMessage(vector.input.messageType ?? "", bytes) else {
            return VectorOutcome(
                id: vector.id, category: manualCategory, outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        if vector.expectedError != nil { return manualVerdictOutcome(vector, decoded.verdict) }
        guard let expectedSummary = vector.expected?.summary, let expectedSha = vector.expected?.messageSha256 else {
            throw ConformanceFailure(description: "manual-pairing vector \(vector.id) missing expected fields")
        }
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let passed = decoded.verdict == "accepted" && decoded.summary == expectedSummary
            && decoded.reencoded == bytes && sha == expectedSha
        return VectorOutcome(
            id: vector.id, category: manualCategory, outcome: passed ? "pass" : "fail",
            expected: expectedSummary, actual: decoded.summary
        )
    }

    private static func decodeManualMessage(_ type: String, _ bytes: Data) -> DecodedManualMessage? {
        switch type {
        case "commitment":
            guard let message = try? Tandem_V1_Commitment(serializedBytes: bytes),
                  let reencoded = try? message.serializedData() else { return nil }
            let verdict = message.hash.count == manualHashLength ? "accepted" : "malformedCommitment"
            return DecodedManualMessage(
                verdict: verdict, summary: "type=commitment|hash=\(message.hash.conformanceRunnerHex)",
                reencoded: reencoded
            )
        case "reveal":
            guard let message = try? Tandem_V1_Reveal(serializedBytes: bytes),
                  let reencoded = try? message.serializedData() else { return nil }
            let verdict = message.nonce.count == manualNonceLength ? "accepted" : "malformedReveal"
            return DecodedManualMessage(
                verdict: verdict, summary: "type=reveal|nonce=\(message.nonce.conformanceRunnerHex)",
                reencoded: reencoded
            )
        default:
            guard let message = try? Tandem_V1_ManualPairResult(serializedBytes: bytes),
                  let reencoded = try? message.serializedData() else { return nil }
            let verdict = message.accepted ? "accepted" : "resultNotAccepted"
            return DecodedManualMessage(
                verdict: verdict, summary: "type=manualPairResult|accepted=\(message.accepted)", reencoded: reencoded
            )
        }
    }

    private static func manualSasOutcome(_ vector: ManualPairingManifest.Vector) throws -> VectorOutcome {
        let inputs = try sasInputs(vector.input)
        guard let expected = vector.expected else {
            throw ConformanceFailure(description: "manual-pairing vector \(vector.id) missing expected fields")
        }
        let actualSas = sas(inputs)
        let commitPhone = commit(role: 0x01, nonce: inputs.noncePhone, inputs).conformanceRunnerHex
        let commitMac = commit(role: 0x02, nonce: inputs.nonceMac, inputs).conformanceRunnerHex
        let passed = expected.commitPhoneHex == commitPhone
            && expected.commitMacHex == commitMac
            && expected.hmacHex == sasHmac(inputs).conformanceRunnerHex
            && expected.sas == actualSas
        return VectorOutcome(
            id: vector.id, category: manualCategory, outcome: passed ? "pass" : "fail",
            expected: expected.sas ?? "", actual: actualSas
        )
    }

    private static func manualSasCompareOutcome(_ vector: ManualPairingManifest.Vector) throws -> VectorOutcome {
        guard let phoneView = vector.input.phoneView, let macView = vector.input.macView else {
            throw ConformanceFailure(description: "manual-pairing vector \(vector.id) missing views")
        }
        let phoneSas = sas(try sasInputs(phoneView))
        let macSas = sas(try sasInputs(macView))
        let outcome = manualVerdictOutcome(vector, phoneSas == macSas ? "accepted" : "sasMismatch")
        guard outcome.outcome == "pass", vector.expectedError == nil else { return outcome }
        return VectorOutcome(
            id: vector.id, category: manualCategory, outcome: vector.expected?.sas == phoneSas ? "pass" : "fail",
            expected: vector.expected?.sas ?? "", actual: phoneSas
        )
    }

    private static func commitmentVerdict(_ input: ManualPairingManifest.Input) throws -> String {
        let inputs = ManualSasInputs(
            noncePhone: Data(), nonceMac: Data(),
            macSpki: try conformanceRunnerHexDecode(input.macSpkiDerHex ?? ""),
            phoneSpki: try conformanceRunnerHexDecode(input.phoneSpkiDerHex ?? ""),
            channelBinding: try conformanceRunnerHexDecode(input.cbHex ?? "")
        )
        let roleByte: UInt8 = input.committerRole == "phone" ? 0x01 : 0x02
        let nonce = try conformanceRunnerHexDecode(input.revealNonceHex ?? "")
        let received = try conformanceRunnerHexDecode(input.commitmentHex ?? "")
        return commit(role: roleByte, nonce: nonce, inputs) == received ? "accepted" : "commitmentMismatch"
    }

    private static func sequenceVerdict(_ observed: [ManualPairingManifest.Message]) -> String {
        guard observed.count <= validSequence.count, observed == Array(validSequence.prefix(observed.count)) else {
            return "outOfOrder"
        }
        return observed.count == validSequence.count ? "accepted" : "incomplete"
    }

    private static func sasInputs(_ view: ManualPairingManifest.SasView) throws -> ManualSasInputs {
        ManualSasInputs(
            noncePhone: try conformanceRunnerHexDecode(view.noncePhoneHex),
            nonceMac: try conformanceRunnerHexDecode(view.nonceMacHex),
            macSpki: try conformanceRunnerHexDecode(view.macSpkiDerHex),
            phoneSpki: try conformanceRunnerHexDecode(view.phoneSpkiDerHex),
            channelBinding: try conformanceRunnerHexDecode(view.cbHex)
        )
    }

    private static func sasInputs(_ input: ManualPairingManifest.Input) throws -> ManualSasInputs {
        try sasInputs(ManualPairingManifest.SasView(
            noncePhoneHex: input.noncePhoneHex ?? "", nonceMacHex: input.nonceMacHex ?? "",
            macSpkiDerHex: input.macSpkiDerHex ?? "", phoneSpkiDerHex: input.phoneSpkiDerHex ?? "",
            cbHex: input.cbHex ?? ""
        ))
    }

    private static func lengthPrefixed(_ bytes: Data) -> Data {
        Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)]) + bytes
    }

    private static func context(_ inputs: ManualSasInputs) -> Data {
        pairLabel + lengthPrefixed(inputs.macSpki) + lengthPrefixed(inputs.phoneSpki)
            + lengthPrefixed(inputs.channelBinding)
    }

    private static func commit(role: UInt8, nonce: Data, _ inputs: ManualSasInputs) -> Data {
        Data(SHA256.hash(data: commitLabel + Data([role]) + nonce + context(inputs)))
    }

    private static func sasHmac(_ inputs: ManualSasInputs) -> Data {
        hmacSha256(key: inputs.noncePhone + inputs.nonceMac, message: pairLabel + context(inputs))
    }

    /// RFC 2104 over CryptoKit's SHA-256: an independent reference for the vectors, since HMAC-SHA256
    /// outside TandemCrypto is banned by `key_material_only_in_crypto`.
    private static func hmacSha256(key: Data, message: Data) -> Data {
        let blockSize = 64
        let paddedKey = (key.count > blockSize ? Data(SHA256.hash(data: key)) : key)
            + Data(count: blockSize - min(key.count > blockSize ? 32 : key.count, blockSize))
        let inner = Data(paddedKey.map { $0 ^ 0x36 }) + message
        return Data(SHA256.hash(data: Data(paddedKey.map { $0 ^ 0x5C }) + Data(SHA256.hash(data: inner))))
    }

    private static func sas(_ inputs: ManualSasInputs) -> String {
        let prefix = sasHmac(inputs).prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return String(format: "%06llu", prefix % sasModulus)
    }
}

struct DecodedManualMessage {
    let verdict: String
    let summary: String
    let reencoded: Data
}

struct ManualSasInputs {
    let noncePhone: Data
    let nonceMac: Data
    let macSpki: Data
    let phoneSpki: Data
    let channelBinding: Data
}

struct ManualPairingManifest: Decodable {
    struct Message: Decodable, Equatable {
        let from: String
        let type: String
    }
    struct SasView: Decodable {
        let noncePhoneHex: String
        let nonceMacHex: String
        let macSpkiDerHex: String
        let phoneSpkiDerHex: String
        let cbHex: String
    }
    struct Input: Decodable {
        let kind: String
        let messageType: String?
        let messageHex: String?
        let noncePhoneHex: String?
        let nonceMacHex: String?
        let macSpkiDerHex: String?
        let phoneSpkiDerHex: String?
        let cbHex: String?
        let committerRole: String?
        let commitmentHex: String?
        let revealNonceHex: String?
        let phoneView: SasView?
        let macView: SasView?
        let messages: [Message]?
    }
    struct Expected: Decodable {
        let summary: String?
        let messageSha256: String?
        let commitPhoneHex: String?
        let commitMacHex: String?
        let hmacHex: String?
        let sas: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
