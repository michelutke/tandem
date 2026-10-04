import Foundation
import SwiftProtobuf

/// What the first length-prefixed frame body on a pinned peer's connection is
/// (`docs/protocol/SPEC.md` § Media ticket: the first frame itself distinguishes a control
/// connection, whose body is an `Envelope`, from a media connection, whose body is a bare
/// `MediaHello`).
public enum FirstFrame: Sendable, Equatable {
    /// The body decodes as an `Envelope` carrying a payload -- the control-connection path.
    case envelope
    /// The body is a `MediaHello`; `ticket` is `nil` when the field is absent or empty. Neither
    /// length is checked here -- the ticket validator owns SPEC case 0 and the media acceptor owns
    /// the 16-byte `mirrorSessionId` (empty when absent).
    case mediaHello(ticket: Data?, mirrorSessionId: Data)
    /// The body is neither.
    case malformed
}

public enum FirstFrameClassifier {
    public static func classify(body: Data) -> FirstFrame {
        if let envelope = try? Tandem_V1_Envelope(serializedBytes: body), envelope.payload != nil {
            return .envelope
        }
        guard let hello = try? Tandem_V1_MediaHello(serializedBytes: body) else { return .malformed }
        return .mediaHello(ticket: hello.ticket.isEmpty ? nil : hello.ticket, mirrorSessionId: hello.mirrorSessionID)
    }
}
