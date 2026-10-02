import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// E15-02: aggregates every `protocol/vectors/` category against the real Swift codec/crypto
/// implementations behind one explicit category -> handler table. A category on disk that is not
/// in this table is an error, never a silent skip ([UnknownVectorCategoryError]).
/// `deferredCategories` names the categories this platform cannot run yet, and the issue that will
/// add them; `notApplicableCategories` names categories that are Android-only by design (macOS
/// never parses a QR payload itself).
///
/// Lives in `TandemProtocolTests` because that target already has (or, for `TandemCrypto`, now
/// declares) every product this runner calls into: `TandemProtocol` (frame codec, display-string
/// sanitizer) and `TandemCrypto` (SPKI fingerprint, pairing proof / confirmation code) -- reusing
/// the existing package graph instead of adding a new SwiftPM target (KISS). Per-category handlers
/// live in `ConformanceRunner+*.swift` to keep this file (and each of those) short.
enum ConformanceRunner {
    struct VectorOutcome {
        let id: String
        let category: String
        let outcome: String
        let expected: String
        let actual: String
    }

    /// A category present on disk under `protocol/vectors/` that this runner's table does not know.
    struct UnknownVectorCategoryError: Error, CustomStringConvertible {
        let category: String
        var description: String { "unknown vector category on disk: \(category)" }
    }

    /// Thrown by ``assertAllPassed(_:)`` naming every failing vector, hex included.
    struct ConformanceFailure: Error, CustomStringConvertible {
        let description: String
    }

    static let deferredCategories: [String: String] = [:]
    static let notApplicableCategories: [String: String] = ["qr-payload": "not applicable on macOS"]
    static let handledCategories: Set<String> = [
        "frame-encoding", "heartbeat", "spki-fingerprint", "pairing-proof", "display-strings",
        "discovery-id", "status-encoding", "notify-encoding", "clipboard-encoding", "files-encoding",
        "photos-encoding", "contacts-encoding", "sms-encoding", "calls-encoding", "filenames"
    ]

    static func run(directory: URL) async throws -> [VectorOutcome] {
        var outcomes: [VectorOutcome] = []
        for (category, data) in try manifestFiles(directory: directory) {
            outcomes += try await categoryOutcomes(category: category, data: data)
        }
        return outcomes
    }

    private static func categoryOutcomes(category: String, data: Data) async throws -> [VectorOutcome] {
        if let reason = deferredCategories[category] {
            return try skippedOutcomes(data: data, category: category, note: "not implemented: deferred to \(reason)")
        }
        if let reason = notApplicableCategories[category] {
            return try skippedOutcomes(data: data, category: category, note: reason)
        }
        guard handledCategories.contains(category) else {
            throw UnknownVectorCategoryError(category: category)
        }
        return try await runCategory(category, data: data)
    }

    /// Every vector entry across every manifest under `directory`, on disk right now.
    static func countVectorsOnDisk(directory: URL) throws -> Int {
        try manifestFiles(directory: directory).reduce(0) { total, entry in
            try total + JSONDecoder().decode(VectorsOnly.self, from: entry.data).vectors.count
        }
    }

    /// Throws ``ConformanceFailure`` naming every failing vector's id, category, expected and actual.
    static func assertAllPassed(_ outcomes: [VectorOutcome]) throws {
        let failures = outcomes.filter { $0.outcome == "fail" }
        guard !failures.isEmpty else { return }
        let message = failures
            .map { "\($0.category):\($0.id) expected=\($0.expected) actual=\($0.actual)" }
            .joined(separator: "\n")
        throw ConformanceFailure(description: "\(failures.count) conformance vector(s) failed:\n\(message)")
    }

    static func writeReport(_ outcomes: [VectorOutcome], to reportFile: URL) throws {
        try FileManager.default.createDirectory(
            at: reportFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let records = outcomes.map {
            ReportRecord(
                vectorId: $0.id, category: $0.category, outcome: $0.outcome,
                expected: $0.expected, actual: $0.actual
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(records).write(to: reportFile)
    }

    private struct ReportRecord: Encodable {
        let vectorId: String
        let category: String
        let outcome: String
        let expected: String
        let actual: String
    }

    private struct CategoryProbe: Decodable { let category: String? }
    private struct VectorId: Decodable { let id: String }
    private struct VectorsOnly: Decodable { let vectors: [VectorId] }

    private static func manifestFiles(directory: URL) throws -> [(category: String, data: Data)] {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.compactMap { file in
            let data = try Data(contentsOf: file)
            guard let category = try? JSONDecoder().decode(CategoryProbe.self, from: data).category else {
                return nil
            }
            return (category, data)
        }
    }

    private static func skippedOutcomes(data: Data, category: String, note: String) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(VectorsOnly.self, from: data)
        return manifest.vectors.map {
            VectorOutcome(id: $0.id, category: category, outcome: "skipped", expected: "", actual: note)
        }
    }

    private static func runCategory(_ category: String, data: Data) async throws -> [VectorOutcome] {
        switch category {
        case "frame-encoding": return try await runFrameEncoding(data: data)
        case "heartbeat": return try await runHeartbeat(data: data)
        case "status-encoding": return try await runFrameRoundTrip(category: "status-encoding", data: data)
        case "notify-encoding": return try await runFrameRoundTrip(category: "notify-encoding", data: data)
        case "sms-encoding": return try await runSmsEncoding(data: data)
        case "calls-encoding": return try runCallsEncoding(data: data)
        default: return try runSynchronousCategory(category, data: data)
        }
    }

    private static func runSynchronousCategory(_ category: String, data: Data) throws -> [VectorOutcome] {
        switch category {
        case "spki-fingerprint": return try runSpkiFingerprint(data: data)
        case "pairing-proof": return try runPairingProof(data: data)
        case "display-strings": return try runDisplayStrings(data: data)
        case "discovery-id": return try runDiscoveryId(data: data)
        case "clipboard-encoding": return try runClipboardEncoding(data: data)
        case "files-encoding": return try runFilesEncoding(data: data)
        case "photos-encoding": return try runPhotosEncoding(data: data)
        case "contacts-encoding": return try runContactsEncoding(data: data)
        case "filenames": return try runFilenames(data: data)
        default: throw UnknownVectorCategoryError(category: category)
        }
    }

}

extension Data {
    var conformanceRunnerHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

func conformanceRunnerHexDecode(_ hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else {
        throw ConformanceRunner.ConformanceFailure(description: "odd-length hex string")
    }
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            throw ConformanceRunner.ConformanceFailure(description: "invalid hex byte in \(hex)")
        }
        data.append(byte)
        index = next
    }
    return data
}
