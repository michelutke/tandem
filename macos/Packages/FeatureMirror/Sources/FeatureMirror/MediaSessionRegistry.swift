import Foundation
import TandemCrypto
import TandemProtocol
import TandemTransport

/// Ties each media connection to its control session (E60-04, `docs/protocol/SPEC.md` § Media
/// ticket): at most one media connection per control session, closed and its tickets revoked the
/// moment the control session leaves Ready (closed, failed or dead), and only ever bound for the
/// same pinned peer SPKI the control session authenticated as (invariant 3).
public actor MediaSessionRegistry<C: Clock<Duration> & Sendable> {
    private struct Entry {
        let peer: SpkiFingerprint
        var media: (any ByteStreamConnection)?
        let watcher: Task<Void, Never>
    }

    private let issuer: MediaTicketIssuer<C>
    private var entries: [MediaSessionID: Entry] = [:]

    public init(issuer: MediaTicketIssuer<C>) {
        self.issuer = issuer
    }

    /// Starts tracking `session`; a state other than Ready ends it. Re-registering `id` ends the prior entry.
    public func register(session: any TandemSession, id: MediaSessionID, peer: SpkiFingerprint) {
        end(id)
        let states = session.state
        let watcher = Task { [weak self] in
            for await state in states where Self.isTerminal(state) {
                break
            }
            guard !Task.isCancelled else { return }
            await self?.end(id)
        }
        entries[id] = Entry(peer: peer, media: nil, watcher: watcher)
    }

    /// Answers `RequestMediaTicket`: closes any active media connection for `id` first, then issues.
    /// `nil` when `id` is not a live control session.
    public func requestTicket(for id: MediaSessionID) -> IssuedMediaTicket? {
        guard var entry = entries[id] else { return nil }
        entry.media?.cancel()
        entry.media = nil
        entries[id] = entry
        return issuer.issue(session: id, peer: entry.peer)
    }

    /// Adopts a validated media connection. Cancels it and returns `false` when `id` has ended, the
    /// presenting peer is not the control peer, or a media connection is already active.
    @discardableResult
    public func bind(
        _ connection: any ByteStreamConnection,
        to id: MediaSessionID,
        presentedBy peer: SpkiFingerprint
    ) -> Bool {
        guard var entry = entries[id], entry.peer == peer, entry.media == nil else {
            connection.cancel()
            return false
        }
        entry.media = connection
        entries[id] = entry
        return true
    }

    public func hasActiveMedia(for id: MediaSessionID) -> Bool {
        entries[id]?.media != nil
    }

    private func end(_ id: MediaSessionID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.watcher.cancel()
        entry.media?.cancel()
        issuer.sessionEnded(id)
    }

    private static func isTerminal(_ state: ConnectionStateMachine.ConnectionState) -> Bool {
        switch state {
        case .dead, .failed: true
        case .disconnected(let reason): reason != nil
        case .accepted, .tlsHandshaking, .helloExchange, .ready: false
        }
    }
}
