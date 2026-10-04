import Foundation
import Synchronization
import TandemCrypto

/// Identifies one authenticated control session; a ticket is bound to the session that requested it.
public struct MediaSessionID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Why a presented ticket was rejected (`docs/protocol/SPEC.md` § Media ticket, cases 0-5). The
/// connection close is `TICKET_REJECTED` for all; the local reasons map as `missing` -> MISSING,
/// `unknown`/`consumed` -> REUSED, `peerMismatch`/`revoked` -> OTHER_SESSION, `expired` -> EXPIRED.
public enum MediaTicketError: Error, Equatable, Sendable {
    case missing
    case unknown
    case peerMismatch
    case revoked
    case expired
    case consumed
}

/// Constant-time comparison seam for ticket bytes (invariant 6); production is TandemCrypto's helper.
public typealias MediaTicketComparator = @Sendable (Data, Data) -> Bool

/// In-memory ticket records shared by ``MediaTicketIssuer`` and ``MediaTicketValidator``. Records are
/// retained, marked, until exactly 30 s after issuance so rejections stay distinguishable (D-65);
/// never persisted, never logged.
public final class MediaTicketTable<C: Clock<Duration> & Sendable>: Sendable, CustomStringConvertible {
    public static var ticketByteCount: Int { 32 }
    public static var lifetime: Duration { .seconds(30) }

    private struct Record {
        let ticket: Data
        let session: MediaSessionID
        let peer: SpkiFingerprint
        let expiresAt: Duration
        var consumed = false
        var sessionEnded = false
    }

    private let clock: C
    private let origin: C.Instant
    private let comparator: MediaTicketComparator
    private let records = Mutex<[Record]>([])

    public init(clock: C, comparator: @escaping MediaTicketComparator = constantTimeEquals) {
        self.clock = clock
        self.origin = clock.now
        self.comparator = comparator
    }

    public var description: String { "MediaTicketTable" }

    func insert(ticket: Data, session: MediaSessionID, peer: SpkiFingerprint) -> Duration {
        let now = elapsed()
        let expiresAt = now + Self.lifetime
        records.withLock { records in
            purge(&records, now: now)
            for index in records.indices where records[index].session == session {
                records[index].consumed = true
            }
            records.append(Record(ticket: ticket, session: session, peer: peer, expiresAt: expiresAt))
        }
        return expiresAt
    }

    func endSession(_ session: MediaSessionID) {
        let now = elapsed()
        records.withLock { records in
            purge(&records, now: now)
            for index in records.indices where records[index].session == session {
                records[index].sessionEnded = true
            }
        }
    }

    func consume(ticket: Data?, presentingSpki: SpkiFingerprint) throws(MediaTicketError) -> MediaSessionID {
        guard let ticket, ticket.count == Self.ticketByteCount else { throw .missing }
        let now = elapsed()
        return try records.withLock { records throws(MediaTicketError) in
            purge(&records, now: now)
            var matchIndex: Int?
            for index in records.indices where comparator(ticket, records[index].ticket) {
                matchIndex = index
            }
            guard let index = matchIndex else { throw .unknown }
            guard records[index].peer == presentingSpki else {
                records[index].consumed = true
                throw .peerMismatch
            }
            if records[index].sessionEnded { throw .revoked }
            if now >= records[index].expiresAt { throw .expired }
            if records[index].consumed { throw .consumed }
            records[index].consumed = true
            return records[index].session
        }
    }

    private func elapsed() -> Duration {
        origin.duration(to: clock.now)
    }

    private func purge(_ records: inout [Record], now: Duration) {
        records.removeAll { now > $0.expiresAt }
    }
}
