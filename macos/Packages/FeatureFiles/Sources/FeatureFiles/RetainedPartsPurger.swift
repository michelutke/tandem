import Foundation
import TandemCrypto
import TandemStore

/// Deletes the retained `.part` staging files bound to one peer (``FileReceiver/resumeRetained()``)
/// when that peer is unpaired (E14-13), so no partial file outlives the pairing.
public struct RetainedPartsPurger: PeerDataPurging {
    private let staging: URL

    public init(staging: URL) {
        self.staging = staging
    }

    public func purgeAll(peer: SpkiFingerprint) async throws {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        for name in names where name.hasSuffix(".part") {
            let partURL = staging.appendingPathComponent(name)
            guard PartAttributes.read(from: partURL)?.peer == peer.hexString else { continue }
            try FileManager.default.removeItem(at: partURL)
        }
    }
}
