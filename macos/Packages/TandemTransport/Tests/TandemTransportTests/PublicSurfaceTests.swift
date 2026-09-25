import Foundation
import Testing
@testable import TandemTransport

/// Static grep-style regression guard (D-67/cycle 8), analogous in spirit to
/// `tools/lint/release-log-check.rb`'s text-scanning approach: no channel-binding or exporter API
/// of any kind may ever appear in this package's production sources.
@Suite("Public surface")
struct PublicSurfaceTests {

    @Test
    func tandemSession_publicSurface_noChannelBindingOrExporterProperty() throws {
        let forbidden = [
            "channelbinding",
            "exporter",
            "createsecret",
            "sec_protocol_metadata_create_secret"
        ]

        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TandemTransportTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Sources")
            .appendingPathComponent("TandemTransport")

        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil)
        )
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }

        #expect(!files.isEmpty)

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8).lowercased()
            for term in forbidden {
                #expect(
                    !contents.contains(term),
                    "\(file.lastPathComponent) contains forbidden term \"\(term)\""
                )
            }
        }
    }
}
