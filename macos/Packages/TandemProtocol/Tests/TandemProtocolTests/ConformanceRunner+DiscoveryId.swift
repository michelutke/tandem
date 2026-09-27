import Foundation
import TandemCrypto
import TandemProtocol

/// `discovery-id` category handler for ``ConformanceRunner`` (E21-02): exercises the rotating-id
/// advertiser side (``DiscoveryRotatingId``, TandemCrypto) and receiver side
/// (``DiscoveryRotatingId/recognize(advertisedIdHex:candidateHexIds:)``,
/// ``DiscoveryTxtRecord/parse(fields:)``, TandemProtocol) against every vector "kind" in
/// `protocol/vectors/discovery-id.json`: `computeId`, `recognition`, `txtRecord`.
extension ConformanceRunner {
    struct DiscoveryIdInput: Decodable {
        let kind: String
        // computeId
        let macSpkiFingerprintHex: String?
        let unixSecondsUtc: Int64?
        // recognition
        let pairedMacSpkiFingerprintHex: String?
        let receiverUnixSecondsUtc: Int64?
        let advertisedSpkiFingerprintHex: String?
        let advertisedDayIndex: Int64?
        // txtRecord
        // swiftlint:disable:next identifier_name
        let v: String?
        let idHex: String?
        let extraKeys: [String: String]?
        let candidateIdHex: String?
    }

    struct DiscoveryIdExpected: Decodable {
        // computeId
        let dayIndex: Int64?
        let idHex: String?
        // recognition
        let receiverDayIndex: Int64?
        let candidateIdsHex: [String]?
        let advertisedIdHex: String?
        let recognized: Bool?
    }

    struct DiscoveryIdVectorEntry: Decodable {
        let id: String
        let input: DiscoveryIdInput
        let expected: DiscoveryIdExpected?
        let expectedError: String?
    }

    struct DiscoveryIdManifest: Decodable { let vectors: [DiscoveryIdVectorEntry] }

    static func runDiscoveryId(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(DiscoveryIdManifest.self, from: data)
        return try manifest.vectors.map { entry in
            switch entry.input.kind {
            case "computeId": return try discoveryIdComputeIdOutcome(entry)
            case "recognition": return try discoveryIdRecognitionOutcome(entry)
            case "txtRecord": return discoveryIdTxtRecordOutcome(entry)
            default:
                throw ConformanceFailure(description: "vector \(entry.id) has unknown kind \(entry.input.kind)")
            }
        }
    }

    private static func discoveryIdComputeIdOutcome(_ entry: DiscoveryIdVectorEntry) throws -> VectorOutcome {
        guard
            let fingerprintHex = entry.input.macSpkiFingerprintHex,
            let unixSecondsUtc = entry.input.unixSecondsUtc,
            let expected = entry.expected,
            let expectedDayIndex = expected.dayIndex,
            let expectedIdHex = expected.idHex
        else {
            throw ConformanceFailure(description: "vector \(entry.id) is a malformed computeId entry")
        }

        let fingerprint = try conformanceRunnerHexDecode(fingerprintHex)
        let dayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc: unixSecondsUtc)
        let idHex = DiscoveryRotatingId.computeHex(macSpkiFingerprint: fingerprint, dayIndex: dayIndex)

        let passed = dayIndex == expectedDayIndex && idHex == expectedIdHex
        return VectorOutcome(
            id: entry.id, category: "discovery-id", outcome: passed ? "pass" : "fail",
            expected: "dayIndex=\(expectedDayIndex) idHex=\(expectedIdHex)",
            actual: "dayIndex=\(dayIndex) idHex=\(idHex)"
        )
    }

    private static func discoveryIdRecognitionOutcome(_ entry: DiscoveryIdVectorEntry) throws -> VectorOutcome {
        guard
            let pairedHex = entry.input.pairedMacSpkiFingerprintHex,
            let receiverUnixSecondsUtc = entry.input.receiverUnixSecondsUtc,
            let advertisedHex = entry.input.advertisedSpkiFingerprintHex,
            let advertisedDayIndex = entry.input.advertisedDayIndex
        else {
            throw ConformanceFailure(description: "vector \(entry.id) is a malformed recognition entry")
        }

        let pairedFingerprint = try conformanceRunnerHexDecode(pairedHex)
        let advertisedFingerprint = try conformanceRunnerHexDecode(advertisedHex)

        let receiverDayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc: receiverUnixSecondsUtc)
        let candidateIdsHex = DiscoveryRotatingId.candidateHexIds(
            macSpkiFingerprint: pairedFingerprint, receiverUnixSecondsUtc: receiverUnixSecondsUtc
        )
        let advertisedIdHex = DiscoveryRotatingId.computeHex(
            macSpkiFingerprint: advertisedFingerprint, dayIndex: advertisedDayIndex
        )

        if let expected = entry.expected {
            return discoveryIdRecognitionExpectedOutcome(
                entry, receiverDayIndex: receiverDayIndex, candidateIdsHex: candidateIdsHex,
                advertisedIdHex: advertisedIdHex, expected: expected
            )
        }

        let expectedError = entry.expectedError ?? "unknown"
        var actualError = "no error thrown"
        do {
            try DiscoveryRotatingId.recognize(advertisedIdHex: advertisedIdHex, candidateHexIds: candidateIdsHex)
        } catch DiscoveryRotatingId.RecognitionError.notRecognized {
            actualError = "notRecognized"
        } catch {
            actualError = "threw \(error)"
        }
        let passed = actualError == expectedError
        return VectorOutcome(
            id: entry.id, category: "discovery-id", outcome: passed ? "pass" : "fail",
            expected: expectedError, actual: actualError
        )
    }

    private static func discoveryIdRecognitionExpectedOutcome(
        _ entry: DiscoveryIdVectorEntry,
        receiverDayIndex: Int64,
        candidateIdsHex: [String],
        advertisedIdHex: String,
        expected: DiscoveryIdExpected
    ) -> VectorOutcome {
        let expectedDescription = "receiverDayIndex=\(String(describing: expected.receiverDayIndex)) " +
            "candidateIdsHex=\(String(describing: expected.candidateIdsHex)) " +
            "advertisedIdHex=\(String(describing: expected.advertisedIdHex))"
        let actualDescription = "receiverDayIndex=\(receiverDayIndex) candidateIdsHex=\(candidateIdsHex) " +
            "advertisedIdHex=\(advertisedIdHex)"

        var passed = receiverDayIndex == expected.receiverDayIndex
            && candidateIdsHex == (expected.candidateIdsHex ?? [])
            && advertisedIdHex == (expected.advertisedIdHex ?? "")
        do {
            try DiscoveryRotatingId.recognize(advertisedIdHex: advertisedIdHex, candidateHexIds: candidateIdsHex)
        } catch {
            passed = false
        }

        return VectorOutcome(
            id: entry.id, category: "discovery-id", outcome: passed ? "pass" : "fail",
            expected: expectedDescription, actual: actualDescription
        )
    }

    private static func discoveryIdTxtRecordOutcome(_ entry: DiscoveryIdVectorEntry) -> VectorOutcome {
        var fields: [String: String] = [:]
        if let version = entry.input.v { fields["v"] = version }
        if let idHex = entry.input.idHex { fields["id"] = idHex }
        if let extraKeys = entry.input.extraKeys {
            for (key, value) in extraKeys { fields[key] = value }
        }

        let expectedError = entry.expectedError ?? "unknown"
        var actualError = "no error thrown"
        do {
            let parsed = try DiscoveryTxtRecord.parse(fields: fields)
            if let candidateIdHex = entry.input.candidateIdHex {
                try DiscoveryRotatingId.recognize(advertisedIdHex: parsed.idHex, candidateHexIds: [candidateIdHex])
            }
        } catch DiscoveryTxtRecord.ValidationError.malformedTxtRecord {
            actualError = "malformedTxtRecord"
        } catch DiscoveryTxtRecord.ValidationError.unsupportedVersion {
            actualError = "unsupportedVersion"
        } catch DiscoveryRotatingId.RecognitionError.notRecognized {
            actualError = "notRecognized"
        } catch {
            actualError = "threw \(error)"
        }

        let passed = actualError == expectedError
        return VectorOutcome(
            id: entry.id, category: "discovery-id", outcome: passed ? "pass" : "fail",
            expected: expectedError, actual: actualError
        )
    }
}
