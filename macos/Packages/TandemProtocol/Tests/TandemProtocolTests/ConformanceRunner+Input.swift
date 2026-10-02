import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `input-encoding` category handler for ``ConformanceRunner`` (E62-01): decodes the serialized
/// `InputEvent` each vector carries (`input.messageHex`), applies the SPEC.md #input-events
/// validation rules against the vector's active session and window, and compares the result with
/// `expectedError` or `expected.summary`; see `protocol/vectors/README.md`.
extension ConformanceRunner {
    private static let inputCategory = "input-encoding"
    private static let sessionIdLength = 16
    private static let maxTextCharacters = 4096
    private static let maxSwipeDurationMs: UInt32 = 5000
    private static let maxDeleteBackward: UInt32 = 64
    private static let knownGlobalActions: Set<Tandem_V1_GlobalActionKind> = [.back, .home, .recents, .notifications]

    static func runInputEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(InputEncodingManifest.self, from: data)
        return try manifest.vectors.map(inputEncodingOutcome)
    }

    private static func inputEncodingOutcome(_ vector: InputEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex)
        guard let decoded = try? Tandem_V1_InputEvent(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: inputCategory, outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        let activeSession = try conformanceRunnerHexDecode(vector.input.activeSessionIdHex)
        let verdict = inputVerdict(decoded, activeSession: activeSession, input: vector.input)
        if let expectedError = vector.expectedError {
            return VectorOutcome(
                id: vector.id, category: inputCategory, outcome: verdict == expectedError ? "pass" : "fail",
                expected: expectedError, actual: verdict
            )
        }
        guard let expectedSummary = vector.expected?.summary, let expectedSha = vector.expected?.messageSha256 else {
            throw ConformanceFailure(description: "input-encoding vector \(vector.id) missing expected fields")
        }
        let actualSummary = inputSummary(decoded)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let passed = verdict == "accepted" && actualSummary == expectedSummary
            && (try? decoded.serializedData()) == bytes && sha == expectedSha
        return VectorOutcome(
            id: vector.id, category: inputCategory, outcome: passed ? "pass" : "fail",
            expected: expectedSummary, actual: actualSummary
        )
    }

    private static func inputVerdict(
        _ event: Tandem_V1_InputEvent, activeSession: Data, input: InputEncodingManifest.Input
    ) -> String {
        if event.sessionID.count != sessionIdLength { return "missingSessionReference" }
        if event.sessionID != activeSession { return "sessionMismatch" }
        switch event.event {
        case .tap(let tap)?:
            return pointVerdict(tap.x, tap.y, input)
        case .swipe(let swipe)?:
            return swipeVerdict(swipe, input)
        case .scroll(let scroll)?:
            return pointVerdict(scroll.x, scroll.y, input)
        case .globalAction(let action)?:
            return knownGlobalActions.contains(action.action) ? "accepted" : "unknownGlobalAction"
        case .setText(let setText)?:
            return textVerdict(setText.text)
        case .textEdit(let edit)?:
            return textEditVerdict(edit)
        case nil:
            return "unknownPayloadType"
        }
    }

    private static func pointVerdict(_ xPos: UInt32, _ yPos: UInt32, _ input: InputEncodingManifest.Input) -> String {
        xPos < input.windowWidth && yPos < input.windowHeight ? "accepted" : "coordinatesOutOfRange"
    }

    private static func swipeVerdict(_ swipe: Tandem_V1_Swipe, _ input: InputEncodingManifest.Input) -> String {
        let start = pointVerdict(swipe.x1, swipe.y1, input)
        let end = pointVerdict(swipe.x2, swipe.y2, input)
        if start != "accepted" || end != "accepted" { return "coordinatesOutOfRange" }
        return (1...maxSwipeDurationMs).contains(swipe.durationMs) ? "accepted" : "durationOutOfRange"
    }

    private static func textVerdict(_ text: String) -> String {
        text.unicodeScalars.count <= maxTextCharacters ? "accepted" : "textTooLong"
    }

    private static func textEditVerdict(_ edit: Tandem_V1_TextEdit) -> String {
        switch edit.edit {
        case .insert(let text)?: return textVerdict(text)
        case .deleteBackward(let count)?:
            return (1...maxDeleteBackward).contains(count) ? "accepted" : "deleteCountOutOfRange"
        case .imeEnter?, nil: return "accepted"
        }
    }

    private static func inputSummary(_ event: Tandem_V1_InputEvent) -> String {
        switch event.event {
        case .tap(let tap)?:
            return "variant=tap|x=\(tap.x)|y=\(tap.y)"
        case .swipe(let swipe)?:
            return "variant=swipe|x1=\(swipe.x1)|y1=\(swipe.y1)|x2=\(swipe.x2)|y2=\(swipe.y2)"
                + "|durationMs=\(swipe.durationMs)"
        case .scroll(let scroll)?:
            return "variant=scroll|x=\(scroll.x)|y=\(scroll.y)|dx=\(scroll.dx)|dy=\(scroll.dy)"
        case .globalAction(let action)?:
            return "variant=globalAction|action=\(action.action.rawValue)"
        case .setText(let setText)?:
            return "variant=setText|text=\(setText.text)"
        case .textEdit(let edit)?:
            return textEditSummary(edit)
        case nil:
            return "variant=unset"
        }
    }

    private static func textEditSummary(_ edit: Tandem_V1_TextEdit) -> String {
        switch edit.edit {
        case .insert(let text)?: return "variant=textEdit|insert=\(text)"
        case .deleteBackward(let count)?: return "variant=textEdit|deleteBackward=\(count)"
        case .imeEnter?: return "variant=textEdit|imeEnter"
        case nil: return "variant=textEdit|unset"
        }
    }
}

struct InputEncodingManifest: Decodable {
    struct Input: Decodable {
        let messageHex: String
        let activeSessionIdHex: String
        let windowWidth: UInt32
        let windowHeight: UInt32
    }
    struct Expected: Decodable {
        let summary: String?
        let messageSha256: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
