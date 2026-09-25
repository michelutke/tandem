import Foundation

/// Discovers and merges `frame-encoding` category vector manifests under a directory at runtime
/// (E11-12): every `*.json` file directly in the directory whose top-level `"category"` field is
/// `"frame-encoding"` has its `vectors` array appended. This means adding a new frame-encoding
/// fixture file to the directory increases the vector count with no code change; files for other
/// categories (e.g. `spki-fingerprint.json`) are skipped because their `category` differs.
enum FrameVectorLoader {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    private struct CategoryProbe: Decodable {
        let category: String?
    }

    static let frameEncodingCategory = "frame-encoding"

    /// `#filePath` is this source file's on-disk path; walk up to the repo root (mirrors
    /// `FrameEncodingVectorFixture.load()`'s original layout-dependent walk:
    /// `.../macos/Packages/TandemProtocol/Tests/TandemProtocolTests/<file>` -> repo root).
    static func repoRoot(from filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url
    }

    /// Loads every `frame-encoding` manifest under `protocol/vectors` in the repo this test file
    /// lives in.
    static func loadDefault() throws -> FrameEncodingVectorFixture.Manifest {
        try load(directory: repoRoot().appendingPathComponent("protocol/vectors"))
    }

    /// Loads and merges every `frame-encoding` category manifest directly under `directory`
    /// (non-recursive).
    static func load(directory: URL) throws -> FrameEncodingVectorFixture.Manifest {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let jsonFiles = contents
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var vectors: [FrameEncodingVectorFixture.Entry] = []
        var foundAny = false
        for file in jsonFiles {
            let data = try Data(contentsOf: file)
            guard let category = try? JSONDecoder().decode(CategoryProbe.self, from: data).category,
                  category == frameEncodingCategory
            else {
                continue
            }
            let manifest = try JSONDecoder().decode(FrameEncodingVectorFixture.Manifest.self, from: data)
            vectors += manifest.vectors
            foundAny = true
        }
        guard foundAny else {
            throw LoadError(description: "no \(frameEncodingCategory) manifest found under \(directory.path)")
        }
        return FrameEncodingVectorFixture.Manifest(vectors: vectors)
    }
}
