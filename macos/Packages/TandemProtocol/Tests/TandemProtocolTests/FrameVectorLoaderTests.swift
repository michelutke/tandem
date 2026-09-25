import Foundation
import Testing
@testable import TandemProtocol

/// E11-12: `FrameVectorLoader` discovers frame-encoding fixtures at runtime by scanning a
/// directory, rather than a hardcoded filename — so adding a fixture file increases the executed
/// vector count with no code change.
struct FrameVectorLoaderTests {
    @Test
    func frameVectorLoader_extraFixtureInDirectory_discoveredWithoutCodeChange() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeManifest(named: "first.json", vectorId: "loader-test-1", in: tempDir)
        let firstLoad = try FrameVectorLoader.load(directory: tempDir)
        #expect(firstLoad.vectors.count == 1)

        try writeManifest(named: "second.json", vectorId: "loader-test-2", in: tempDir)
        let secondLoad = try FrameVectorLoader.load(directory: tempDir)
        #expect(secondLoad.vectors.count == 2)
    }

    private func writeManifest(named filename: String, vectorId: String, in directory: URL) throws {
        let json = """
        {
          "category": "frame-encoding",
          "vectors": [
            { "id": "\(vectorId)", "input": { "frameHex": "00", "lengthPrefix": 0 } }
          ]
        }
        """
        try json.write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
}
