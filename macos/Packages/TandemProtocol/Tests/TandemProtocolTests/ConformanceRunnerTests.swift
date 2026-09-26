import CryptoKit
import Foundation
import TandemCrypto
import Testing
@testable import TandemProtocol

/// E15-02: the conformance runner's own behavior, distinct from the per-category conformance
/// suites ([FrameCodecConformanceTests] and friends) that already exercise each vector category's
/// codec/crypto implementation. Reuses those via [ConformanceRunner]'s category table rather than
/// duplicating their assertions.
struct ConformanceRunnerTests {
    @Test
    func swiftConformanceRunner_realVectorsDirectory_everyCategoryHandledOrDeferredAndSummaryPrinted() async throws {
        let vectorsDir = FrameVectorLoader.repoRoot().appendingPathComponent("protocol/vectors")

        let outcomes = try await ConformanceRunner.run(directory: vectorsDir)
        try ConformanceRunner.assertAllPassed(outcomes)

        let diskCount = try ConformanceRunner.countVectorsOnDisk(directory: vectorsDir)
        let deferredCount = outcomes.filter { $0.outcome == "skipped" }.count
        let executedCount = outcomes.count - deferredCount

        #expect(diskCount == outcomes.count)
        #expect(diskCount - deferredCount == executedCount)
        print(
            "conformance: executed \(executedCount) vectors (\(deferredCount) deferred/skipped) " +
                "out of \(diskCount) on disk"
        )

        let reportFile = FrameVectorLoader.repoRoot()
            .appendingPathComponent("tools/conformance/reports/macos-report.json")
        try ConformanceRunner.writeReport(outcomes, to: reportFile)
        #expect(FileManager.default.fileExists(atPath: reportFile.path))
    }

    @Test
    func swiftConformanceRunner_corruptedExpectedValue_failsWithHexDiff() async throws {
        let spkiDer = P256.Signing.PrivateKey().publicKey.derRepresentation
        let correctHex = spkiDer.hexEncodedForFixture
        let spkiFingerprintHex = try SpkiFingerprint.compute(spkiDer: spkiDer).hexEncodedForFixture
        let corruptedFirstByte = spkiFingerprintHex.hasPrefix("00") ? "ff" : "00"
        let corruptedHex = corruptedFirstByte + spkiFingerprintHex.dropFirst(2)

        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifest = """
        {
          "category": "spki-fingerprint",
          "generatedBy": "test-fixture",
          "vectors": [
            {
              "id": "corrupted-vector",
              "description": "deliberately wrong expected fingerprint",
              "input": { "spkiDerHex": "\(correctHex)" },
              "expected": { "fingerprintHex": "\(corruptedHex)" }
            }
          ]
        }
        """
        try manifest.write(
            to: tempDir.appendingPathComponent("spki-fingerprint.json"), atomically: true, encoding: .utf8
        )

        let outcomes = try await ConformanceRunner.run(directory: tempDir)
        let failure = try #require(outcomes.first { $0.outcome == "fail" })
        #expect(failure.id == "corrupted-vector")
        #expect(failure.expected == corruptedHex)
        #expect(failure.actual == spkiFingerprintHex)

        do {
            try ConformanceRunner.assertAllPassed(outcomes)
            Issue.record("expected assertAllPassed to throw")
        } catch let error as ConformanceRunner.ConformanceFailure {
            #expect(error.description.contains("corrupted-vector"))
            #expect(error.description.contains(corruptedHex))
            #expect(error.description.contains(spkiFingerprintHex))
        }
    }

    @Test
    func swiftConformanceRunner_unknownVectorCategory_failsNamingCategory() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifest = """
        {
          "category": "bogus-category",
          "generatedBy": "test-fixture",
          "vectors": [
            { "id": "bogus-vector", "description": "n/a", "input": {}, "expected": {} }
          ]
        }
        """
        try manifest.write(to: tempDir.appendingPathComponent("bogus.json"), atomically: true, encoding: .utf8)

        do {
            _ = try await ConformanceRunner.run(directory: tempDir)
            Issue.record("expected run(directory:) to throw")
        } catch let error as ConformanceRunner.UnknownVectorCategoryError {
            #expect(error.category == "bogus-category")
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private extension Data {
    var hexEncodedForFixture: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
