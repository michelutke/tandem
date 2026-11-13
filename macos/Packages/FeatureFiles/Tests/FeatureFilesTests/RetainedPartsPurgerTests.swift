import Foundation
import Testing
import TandemCrypto
import TandemProtocol
@testable import FeatureFiles

@Suite("RetainedPartsPurger")
struct RetainedPartsPurgerTests {
    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func writePart(id: String, peer: SpkiFingerprint, in staging: URL) throws -> URL {
        var offer = Tandem_V1_FileOffer()
        offer.id = id
        offer.name = "\(id).bin"
        let url = staging.appendingPathComponent("\(id).part")
        try Data([1, 2, 3]).write(to: url)
        try PartAttributes.write(peer: peer.hexString, offer: offer, to: url)
        return url
    }

    @Test
    func appComposition_unpair_everyStorePurged_retainedPartsOfPeerDeletedOthersKept() async throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let unpaired = try Self.fingerprint(0x01)
        let other = try Self.fingerprint(0x02)
        let mine = try Self.writePart(id: "a", peer: unpaired, in: staging)
        let theirs = try Self.writePart(id: "b", peer: other, in: staging)

        try await RetainedPartsPurger(staging: staging).purgeAll(peer: unpaired)

        #expect(!FileManager.default.fileExists(atPath: mine.path))
        #expect(FileManager.default.fileExists(atPath: theirs.path))
    }

    @Test
    func retainedPartsPurger_storedPeers_listsEveryPeerWithAPart() async throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let first = try Self.fingerprint(0x01)
        let second = try Self.fingerprint(0x02)
        _ = try Self.writePart(id: "a", peer: first, in: staging)
        _ = try Self.writePart(id: "b", peer: second, in: staging)
        _ = try Self.writePart(id: "c", peer: second, in: staging)

        let peers = try await RetainedPartsPurger(staging: staging).storedPeers()

        #expect(Set(peers) == [first, second])
    }
}
