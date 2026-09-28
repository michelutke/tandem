import Foundation
import TandemCrypto
import Testing
@testable import TandemProtocol

/// E21-07's own skew-boundary tdd names, distinct from `ConformanceRunnerTests`' generic
/// everyVectorPasses sweep (which already exercises every `discovery-id.json` vector, including
/// these): pins down specifically that the `recognition`-kind skew vectors at dayIndex+/-1 are
/// recognized and dayIndex+/-2 are rejected, mirroring `RotatingIdSkewVectorsConformanceTest.kt`
/// on Android -- "on both codecs" in the tdd name means this Swift test and that Kotlin test share
/// a name, each against its own platform's `DiscoveryRotatingId`, not that this one file spans both.
///
/// Invariant 3 (CLAUDE.md): recognition here is a connection-candidate hint only. These tests
/// assert only whether `DiscoveryRotatingId.recognize` accepts/rejects a hex id; they never
/// exercise or imply anything about the mTLS pin check that alone establishes trust.
struct RotatingIdSkewVectorsTests {
    private static func manifest() throws -> ConformanceRunner.DiscoveryIdManifest {
        let url = FrameVectorLoader.repoRoot().appendingPathComponent("protocol/vectors/discovery-id.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ConformanceRunner.DiscoveryIdManifest.self, from: data)
    }

    private static func recognitionVector(_ vectorId: String) throws -> (
        candidateIdsHex: [String], advertisedIdHex: String
    ) {
        let entry = try #require(try manifest().vectors.first { $0.id == vectorId })
        guard
            let pairedHex = entry.input.pairedMacSpkiFingerprintHex,
            let receiverUnixSecondsUtc = entry.input.receiverUnixSecondsUtc,
            let advertisedHex = entry.input.advertisedSpkiFingerprintHex,
            let advertisedDayIndex = entry.input.advertisedDayIndex
        else {
            throw ConformanceRunner.ConformanceFailure(
                description: "vector \(vectorId) is a malformed recognition entry"
            )
        }

        let pairedFingerprint = try conformanceRunnerHexDecode(pairedHex)
        let advertisedFingerprint = try conformanceRunnerHexDecode(advertisedHex)
        let candidateIdsHex = DiscoveryRotatingId.candidateHexIds(
            macSpkiFingerprint: pairedFingerprint, receiverUnixSecondsUtc: receiverUnixSecondsUtc
        )
        let advertisedIdHex = DiscoveryRotatingId.computeHex(
            macSpkiFingerprint: advertisedFingerprint, dayIndex: advertisedDayIndex
        )
        return (candidateIdsHex, advertisedIdHex)
    }

    @Test
    func rotatingIdSkewVectors_plusMinusOneDay_recognizedOnBothCodecs() throws {
        for vectorId in ["discovery-id-skew-minus-one-recognized", "discovery-id-skew-plus-one-recognized"] {
            let vector = try Self.recognitionVector(vectorId)
            #expect(throws: Never.self, "vector \(vectorId)") {
                try DiscoveryRotatingId.recognize(
                    advertisedIdHex: vector.advertisedIdHex, candidateHexIds: vector.candidateIdsHex
                )
            }
        }
    }

    @Test
    func rotatingIdSkewVectors_plusMinusTwoDays_rejectedOnBothCodecs() throws {
        for vectorId in ["discovery-id-skew-minus-two-not-recognized", "discovery-id-skew-plus-two-not-recognized"] {
            let vector = try Self.recognitionVector(vectorId)
            #expect(throws: DiscoveryRotatingId.RecognitionError.notRecognized, "vector \(vectorId)") {
                try DiscoveryRotatingId.recognize(
                    advertisedIdHex: vector.advertisedIdHex, candidateHexIds: vector.candidateIdsHex
                )
            }
        }
    }
}
