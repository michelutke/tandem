import Foundation
import TandemCrypto
import TandemProtocol

/// How the connection that delivered a media candidate was classified by the listener's pin check.
public enum MediaConnectionPeer: Sendable, Equatable {
    case trusted(SpkiFingerprint)
    /// Still inside the pairing window; never eligible to open a media connection (D-25).
    case pairingCandidate
}

/// Local ticket-rejection reasons (`docs/protocol/SPEC.md` § Media ticket, Rejection).
public enum MediaTicketRejectReason: Error, Sendable, Equatable {
    case missing
    case reused
    case otherSession
    case expired
}

/// Validates a presented `MediaHello` ticket against the presenting peer's SPKI and, on success,
/// consumes it. The composition root adapts FeatureMirror's `MediaTicketValidator`; the `UUID` is
/// the originating control session's identifier.
public protocol MediaTicketValidating: Sendable {
    func validate(ticket: Data?, presentingSpki: SpkiFingerprint) -> Result<UUID, MediaTicketRejectReason>
}

/// A media connection bound to its originating control session. `connection` replays any bytes the
/// peer sent after `MediaHello`; no media frame has been read from it.
public struct MediaBinding: Sendable {
    public let sessionID: UUID
    /// The SPKI the media connection authenticated as, equal to the ticket's control peer.
    public let peer: SpkiFingerprint
    /// The phone-minted 16-byte id of the mirror session (D-77), echoed in input messages.
    public let mirrorSessionId: Data
    public let connection: any ByteStreamConnection
}

/// Distinct from a TLS handshake failure; no case carries ticket bytes (invariant 7).
public enum MediaAcceptorEvent: Sendable, Equatable {
    case bound(UUID)
    case ticketRejected(MediaTicketRejectReason)
    case closed(CloseCode)
}

/// Receives a pinned peer's connection whose first frame is not a control `Envelope`.
public protocol MediaConnectionHandling: Sendable {
    func handle(connection: any ByteStreamConnection, peer: MediaConnectionPeer) async
}

/// The media half of the single listener (E60-03, ADR-005): the first frame must be `MediaHello`,
/// arrive within 5 s, and carry a ticket the validator accepts for the presenting peer. Every
/// failure closes the connection before a second frame is read.
public final class MediaConnectionAcceptor: MediaConnectionHandling, Sendable {
    public static let helloDeadline = FirstFrameReader.deadline
    static let mirrorSessionIdLength = 16

    public let events: AsyncStream<MediaAcceptorEvent>
    private let eventContinuation: AsyncStream<MediaAcceptorEvent>.Continuation
    private let validator: any MediaTicketValidating
    private let clock: any Clock<Duration>
    private let onBound: @Sendable (MediaBinding) -> Void

    public init(
        validator: any MediaTicketValidating,
        clock: any Clock<Duration>,
        onBound: @escaping @Sendable (MediaBinding) -> Void
    ) {
        self.validator = validator
        self.clock = clock
        self.onBound = onBound
        (events, eventContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public func handle(connection: any ByteStreamConnection, peer: MediaConnectionPeer) async {
        if let binding = await accept(connection: connection, peer: peer) {
            onBound(binding)
        }
    }

    public func accept(connection: any ByteStreamConnection, peer: MediaConnectionPeer) async -> MediaBinding? {
        let source = ByteStreamConnectionFrameSource(connection)
        let outcome = await FirstFrameReader.read(from: source, clock: clock, onDeadline: { connection.cancel() })
        switch outcome {
        case .timedOut:
            return close(connection, .protocolTimeout)
        case .rejected(let code):
            return close(connection, code)
        case .ended:
            connection.cancel()
            return nil
        case .frame(let body, _):
            guard case .trusted(let spki) = peer else { return close(connection, .malformedFrame) }
            guard case .mediaHello(let ticket, let mirrorSessionId) = FirstFrameClassifier.classify(body: body) else {
                return close(connection, .malformedFrame)
            }
            return bind(
                connection,
                ticket: ticket,
                mirrorSessionId: mirrorSessionId,
                peer: spki,
                leftover: source.takeBuffered()
            )
        }
    }

    private func bind(
        _ connection: any ByteStreamConnection,
        ticket: Data?,
        mirrorSessionId: Data,
        peer: SpkiFingerprint,
        leftover: Data
    ) -> MediaBinding? {
        switch validator.validate(ticket: ticket, presentingSpki: peer) {
        case .success(let sessionID):
            guard mirrorSessionId.count == Self.mirrorSessionIdLength else {
                return close(connection, .malformedFrame)
            }
            eventContinuation.yield(.bound(sessionID))
            return MediaBinding(
                sessionID: sessionID,
                peer: peer,
                mirrorSessionId: mirrorSessionId,
                connection: PrefixedByteStreamConnection(connection, prefix: leftover)
            )
        case .failure(let reason):
            eventContinuation.yield(.ticketRejected(reason))
            connection.cancel()
            return nil
        }
    }

    private func close(_ connection: any ByteStreamConnection, _ code: CloseCode) -> MediaBinding? {
        eventContinuation.yield(.closed(code))
        connection.cancel()
        return nil
    }
}
