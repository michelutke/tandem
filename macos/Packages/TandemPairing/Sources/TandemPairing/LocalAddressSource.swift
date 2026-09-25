import Darwin
import Foundation

/// Seam over `getifaddrs` (E14-01): returns literal IPv4/IPv6 address strings for the Mac's
/// current network interfaces, unfiltered and in whatever order the underlying enumeration
/// reports them. `QrPayloadEncoder` decides which of these are routable enough to publish in a
/// pairing QR code (`docs/protocol/SPEC.md` #2); tests inject a fake conforming to this protocol
/// instead of touching real interfaces, so the encoder stays deterministic.
public protocol LocalAddressSource: Sendable {
    func currentAddresses() -> [String]
}

/// Enumerates local interface addresses via `getifaddrs`. Returns every "up" interface's
/// IPv4/IPv6 literal address, unfiltered; `QrPayloadEncoder` excludes loopback, IPv6 link-local
/// and unspecified addresses and caps the count before encoding.
public struct GetifaddrsLocalAddressSource: LocalAddressSource {
    public init() {}

    public func currentAddresses() -> [String] {
        var addressesHead: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressesHead) == 0 else {
            return []
        }
        defer { freeifaddrs(addressesHead) }

        var literals: [String] = []
        var current = addressesHead
        while let entry = current {
            defer { current = entry.pointee.ifa_next }

            guard entry.pointee.ifa_flags & UInt32(IFF_UP) != 0, let addr = entry.pointee.ifa_addr else {
                continue
            }
            let family = addr.pointee.sa_family
            guard family == sa_family_t(AF_INET) || family == sa_family_t(AF_INET6) else {
                continue
            }
            if let literal = Self.literalAddress(addr) {
                literals.append(literal)
            }
        }
        return literals
    }

    private static func literalAddress(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let socketLength: socklen_t = addr.pointee.sa_family == sa_family_t(AF_INET)
            ? socklen_t(MemoryLayout<sockaddr_in>.size)
            : socklen_t(MemoryLayout<sockaddr_in6>.size)

        let result = getnameinfo(
            addr,
            socketLength,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return hostBuffer.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { String(cString: $0) }
        }
    }
}
