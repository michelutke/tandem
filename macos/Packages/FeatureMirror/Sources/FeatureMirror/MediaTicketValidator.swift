import Foundation
import TandemCrypto

/// Validates a `MediaHello` ticket in the SPEC's ordered cases 0-5 and consumes it on first success
/// (E60-08, invariant 6). The returned session is the one the media connection binds to.
public struct MediaTicketValidator<C: Clock<Duration> & Sendable>: Sendable {
    private let table: MediaTicketTable<C>

    public init(table: MediaTicketTable<C>) {
        self.table = table
    }

    public func validate(ticket: Data?, presentingSpki: SpkiFingerprint) throws(MediaTicketError) -> MediaSessionID {
        try table.consume(ticket: ticket, presentingSpki: presentingSpki)
    }
}
