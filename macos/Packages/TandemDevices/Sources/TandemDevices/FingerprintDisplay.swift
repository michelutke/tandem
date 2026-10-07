import Foundation

/// Short, mono-friendly fingerprint text for the Devices screen: the first eight bytes of a key
/// fingerprint as four groups of four uppercase hex digits ("7F3A 91C2 0B6E D4A8", ui-spec §7.1).
public enum FingerprintDisplay {
    public static func groups(of bytes: Data) -> String {
        regroup(bytes.prefix(8).map { String(format: "%02X", $0) }.joined())
    }

    /// Regroups colon-separated hex ("3C:71:A0:9E:55:F2:8B:1D") into the same four-digit groups.
    public static func regroup(colonSeparated text: String) -> String {
        regroup(text.replacingOccurrences(of: ":", with: "").uppercased())
    }

    private static func regroup(_ hex: String) -> String {
        stride(from: 0, to: hex.count, by: 4)
            .map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: min(4, hex.count - offset))
                return String(hex[start..<end])
            }
            .joined(separator: " ")
    }
}
