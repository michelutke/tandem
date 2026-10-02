import Foundation
import TandemCrypto

/// A freshly issued ticket and the wire `expiresAt` (ms since Unix epoch) for `MediaTicketGrant`.
public struct IssuedMediaTicket: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let ticket: Data
    public let expiresAtMillis: Int64

    public var description: String { "IssuedMediaTicket(expiresAtMillis: \(expiresAtMillis))" }
    public var debugDescription: String { description }
}

/// Answers `RequestMediaTicket` (E60-08): a 32-byte CSPRNG ticket bound to the authenticated control
/// session and peer SPKI, valid 30 s (`docs/protocol/SPEC.md` § Media ticket).
public struct MediaTicketIssuer<C: Clock<Duration> & Sendable>: Sendable {
    private let table: MediaTicketTable<C>
    private let source: MediaTicketSource
    private let dateProvider: @Sendable () -> Date

    public init(table: MediaTicketTable<C>, source: MediaTicketSource, dateProvider: @escaping @Sendable () -> Date) {
        self.table = table
        self.source = source
        self.dateProvider = dateProvider
    }

    /// Supersedes any ticket still outstanding for `session`.
    public func issue(session: MediaSessionID, peer: SpkiFingerprint) -> IssuedMediaTicket {
        let ticket = source.generateTicket()
        _ = table.insert(ticket: ticket, session: session, peer: peer)
        let lifetimeSeconds = TimeInterval(MediaTicketTable<C>.lifetime.components.seconds)
        let expiresAt = dateProvider().addingTimeInterval(lifetimeSeconds)
        let expiresAtMillis = Int64((expiresAt.timeIntervalSince1970 * 1000).rounded())
        return IssuedMediaTicket(ticket: ticket, expiresAtMillis: expiresAtMillis)
    }

    /// Marks every ticket issued to `session` as unbindable (`revoked`).
    public func sessionEnded(_ session: MediaSessionID) {
        table.endSession(session)
    }
}
