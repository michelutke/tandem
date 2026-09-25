import Foundation

/// Sanitizes untrusted peer-supplied display strings before they are ever rendered
/// (`docs/protocol/SPEC.md` "Untrusted peer strings (display sanitization)", E01-23). Every
/// string one peer supplies that the other peer displays -- pairing device names, trust-store
/// entries, notification titles/bodies, file names, SMS senders and bodies, contact names, caller
/// IDs -- MUST pass through here first, regardless of whether the sender is an already-paired,
/// authenticated peer: a compromised-but-still-pinned peer can supply a hostile string just as
/// easily as an unpaired one.
///
/// Mirrors `tools/vectors/display_strings.py`, the reference implementation validated against
/// `protocol/vectors/display-strings.json` (E01-24); the Android twin is `DisplayStringSanitizer`
/// (E14-21).
public enum DisplayStringSanitizer {
    /// The three display-string surfaces SPEC.md defines, each with its own default length cap
    /// counted in Unicode scalar values. `body` is the only multi-line kind: it preserves
    /// U+000A (LINE FEED); `name`/`title` are single-line and additionally collapse whitespace
    /// runs and strip zero-width code points (SPEC.md step 5).
    public enum Kind: String, Sendable {
        case name
        case title
        case body

        var cap: Int {
            switch self {
            case .name: return 64
            case .title: return 256
            case .body: return 4096
            }
        }

        var isMultiLine: Bool {
            self == .body
        }
    }

    private static let bidiControls: Set<UInt32> = [
        0x200E, 0x200F, 0x061C,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069
    ]

    private static let zeroWidth: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]

    private static let ellipsis: Character = "\u{2026}"

    /// Runs SPEC.md's sanitization order, steps 1 through 7, on `rawBytes` interpreted as
    /// peer-supplied UTF-8 for `kind`.
    public static func sanitize(_ rawBytes: Data, kind: Kind) -> String {
        // Step 1 requires every invalid byte sequence to decode as U+FFFD, never dropped and
        // never left as raw bytes: the failable `String(bytes:encoding:)` initializer this rule
        // otherwise prefers returns `nil` on invalid UTF-8, which cannot satisfy that.
        // swiftlint:disable:next optional_data_string_conversion
        var text = String(decoding: rawBytes, as: UTF8.self)
        text = text.precomposedStringWithCanonicalMapping

        text = removingBidiControls(text)
        text = removingControls(text, keepingLineFeed: kind.isMultiLine)

        if !kind.isMultiLine {
            text = removingZeroWidth(text)
            text = collapsingWhitespace(text)
        }

        text = text.precomposedStringWithCanonicalMapping

        return truncated(text, cap: kind.cap)
    }

    private static func removingBidiControls(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !bidiControls.contains($0.value) }))
    }

    /// C0 (U+0000-U+001F) and C1 (U+0080-U+009F) control code points, plus DEL (U+007F): all are
    /// Unicode general category Cc, and none of them belong in a rendered display string.
    private static func isC0OrC1(_ value: UInt32) -> Bool {
        (0x00...0x1F).contains(value) || (0x7F...0x9F).contains(value)
    }

    private static func removingControls(_ text: String, keepingLineFeed: Bool) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            if keepingLineFeed && scalar.value == 0x0A {
                return true
            }
            return !isC0OrC1(scalar.value)
        }))
    }

    private static func removingZeroWidth(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !zeroWidth.contains($0.value) }))
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var previousWasWhitespace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !previousWasWhitespace {
                    result.append(Unicode.Scalar(UInt8(0x20)))
                }
                previousWasWhitespace = true
            } else {
                result.append(scalar)
                previousWasWhitespace = false
            }
        }
        return String(result)
    }

    /// Truncates to `cap` Unicode scalar values, breaking only on an extended-grapheme-cluster
    /// (`Character`) boundary -- a cluster that would straddle the cap is dropped whole, never
    /// split. If truncation occurred, appends a single U+2026; the ellipsis itself does not count
    /// against `cap`.
    private static func truncated(_ text: String, cap: Int) -> String {
        guard text.unicodeScalars.count > cap else {
            return text
        }

        var kept = ""
        var count = 0
        for character in text {
            let scalarCount = character.unicodeScalars.count
            if count + scalarCount > cap {
                break
            }
            kept.append(character)
            count += scalarCount
        }
        kept.append(ellipsis)
        return kept
    }
}
