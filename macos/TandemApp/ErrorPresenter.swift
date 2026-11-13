/// Maps a failure reason to a user-visible, secret-free error string (E12-10, invariant 5).
/// Pure value type; no dependencies on the app state or UI framework.
struct ErrorPresenter: Sendable {
    /// The failure reason, as the name of a CloseCode case (e.g., "versionMismatch", "protocolTimeout").
    let reasonName: String

    /// Title shown in the menu's connection-status area.
    var title: String {
        switch reasonName {
        case "versionMismatch":
            return "error.versionMismatch"
        case "protocolTimeout":
            return "error.timeout"
        case "limitExceeded":
            return "error.unknownPeer"
        case "malformedFrame":
            return "error.malformedFrame"
        case "creditViolation":
            return "error.creditViolation"
        case "pinMismatch":
            return "error.pinMismatch"
        default:
            return "error.unknown"
        }
    }

    /// Localized English text for the title (test-only; production uses Localizable.strings).
    var localizedTitle: String {
        switch reasonName {
        case "versionMismatch":
            return "Version mismatch."
        case "protocolTimeout":
            return "Timeout."
        case "limitExceeded":
            return "Too many connections."
        case "malformedFrame":
            return "Corrupted data received."
        case "creditViolation":
            return "Data flow error."
        case "pinMismatch":
            return "Untrusted device refused."
        default:
            return "Error."
        }
    }

    /// Detail string (secondary text). Empty for now; may be filled in a future issue.
    var detail: String {
        ""
    }
}
