import Darwin
import Foundation
import TandemProtocol

/// Peer fingerprint and original offer stored as extended attributes on a staged `.part` file, so a
/// retained partial transfer is only resumed for the same authenticated peer and transfer id.
enum PartAttributes {
    private static let peerKey = "dev.tandem.part.peer"
    private static let offerKey = "dev.tandem.part.offer"

    static func write(peer: String, offer: Tandem_V1_FileOffer, to url: URL) throws {
        try set(peerKey, Data(peer.utf8), on: url)
        try set(offerKey, try offer.serializedData(), on: url)
    }

    static func read(from url: URL) -> (peer: String, offer: Tandem_V1_FileOffer)? {
        guard let peerData = get(peerKey, on: url),
              let peer = String(data: peerData, encoding: .utf8),
              let offerData = get(offerKey, on: url),
              let offer = try? Tandem_V1_FileOffer(serializedBytes: offerData) else { return nil }
        return (peer, offer)
    }

    private static func set(_ key: String, _ value: Data, on url: URL) throws {
        let status = value.withUnsafeBytes { setxattr(url.path, key, $0.baseAddress, $0.count, 0, 0) }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func get(_ key: String, on url: URL) -> Data? {
        let size = getxattr(url.path, key, nil, 0, 0, 0)
        guard size >= 0 else { return nil }
        var buffer = Data(count: size)
        let read = buffer.withUnsafeMutableBytes { getxattr(url.path, key, $0.baseAddress, size, 0, 0) }
        return read == size ? buffer : nil
    }
}
