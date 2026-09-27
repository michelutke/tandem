import Foundation
import Testing
@testable import TandemCrypto

@Test func rotatingIdVectors_swiftCodec_matchesExpectedIds() throws {
    let manifest = try DiscoveryRotatingIdVectorFixture.load()
    let computeIdEntries = manifest.vectors.filter { $0.input.kind == "computeId" }
    #expect(!computeIdEntries.isEmpty)

    for entry in computeIdEntries {
        guard let expected = entry.expected, let unixSecondsUtc = entry.input.unixSecondsUtc else {
            Issue.record("vector \(entry.id) is a malformed computeId entry")
            continue
        }
        let macSpkiFingerprint = try DiscoveryRotatingIdVectorFixture.macSpkiFingerprint(for: entry)

        let dayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc: unixSecondsUtc)
        #expect(dayIndex == expected.dayIndex, "vector \(entry.id)")

        let idHex = DiscoveryRotatingId.computeHex(macSpkiFingerprint: macSpkiFingerprint, dayIndex: dayIndex)
        #expect(idHex == expected.idHex, "vector \(entry.id)")
    }
}
