import Foundation

/// Minimal machine-readable output for the not-yet-built E15-02/E15-03 conformance runner.
/// Written to `tools/conformance/reports/<filename>` (gitignored, mirrors the `tools/audit/report.json`
/// pattern already used for E15-18's audit runner). Record shape and the two filenames
/// (`frame-codec-valid.json`, `frame-codec-invalid.json`) are the parity contract with the
/// Android twin (E11-11): same relative path, same field names, from whichever platform ran.
enum ConformanceReportWriter {
    struct Record: Encodable {
        let vectorId: String
        let outcome: String
        let expected: String
        let actual: String
    }

    static func write(_ records: [Record], filename: String, repoRoot: URL = FrameVectorLoader.repoRoot()) throws {
        let dir = repoRoot.appendingPathComponent("tools/conformance/reports")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(records)
        try data.write(to: dir.appendingPathComponent(filename))
    }
}
