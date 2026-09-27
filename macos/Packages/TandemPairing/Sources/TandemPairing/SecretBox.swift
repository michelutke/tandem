import Foundation

/// Reference-type holder for ``PairingWindow``'s single-use secret: every `OpenState` copy shares
/// this same instance rather than `Data`'s copy-on-write storage, so ``zero()`` scrubs the one
/// real buffer in place instead of a throwaway copy while the original is later freed unscrubbed.
final class SecretBox {
    private(set) var bytes: [UInt8]

    init(_ data: Data) {
        self.bytes = Array(data)
    }

    var data: Data { Data(bytes) }

    func zero() {
        guard !bytes.isEmpty else { return }
        _ = bytes.withUnsafeMutableBytes { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }
}
