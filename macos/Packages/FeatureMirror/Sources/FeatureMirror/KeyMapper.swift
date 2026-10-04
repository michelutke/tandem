import Foundation

/// Maps a key-down to a `TextEdit` operation (SPEC § Input events). Text comes from the event's
/// layout-resolved characters, so US/ISO layouts need no key tables; no raw key codes are sent.
public enum KeyMapper {
    public enum Edit: Equatable, Sendable {
        case insert(String)
        case deleteBackward(UInt32)
        case imeEnter
    }

    public static let maxInsertCodePoints = 4096

    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76
    private static let deleteKeyCode: UInt16 = 51
    private static let functionKeyScalars: ClosedRange<UInt32> = 0xF700...0xF8FF

    public static func textEdit(characters: String?, keyCode: UInt16, hasCommandModifiers: Bool) -> Edit? {
        guard !hasCommandModifiers else { return nil }
        switch keyCode {
        case returnKeyCode, keypadEnterKeyCode: return .imeEnter
        case deleteKeyCode: return .deleteBackward(1)
        default: break
        }
        guard let characters, !characters.isEmpty else { return nil }
        let scalars = characters.unicodeScalars
        guard scalars.allSatisfy(isInsertable) else { return nil }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: scalars.prefix(maxInsertCodePoints))
        return .insert(String(text))
    }

    private static func isInsertable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory != .control && !functionKeyScalars.contains(scalar.value)
    }
}
