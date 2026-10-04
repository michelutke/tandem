#if DEBUG
import FeatureMirror
import Foundation
import Synchronization
import TandemPairing
import TandemProtocol
import TandemStore
import TandemTransport

/// Debug-only E60-05 hook behind `-HarnessMediaTickets YES`: the real ticket table, issuer, registry,
/// validator adapter and ``MediaConnectionAcceptor`` the app composes (E62-12), without the mirror
/// window or decoder. Every acceptor event is printed as `harness-media-event: <event>` -- reason
/// enums and close codes only, never ticket bytes (invariant 7) -- so a CI driver can tell "mTLS
/// completed, ticket rejected" from "handshake failed". A bound connection also prints
/// `harness-mirror-session: <hex>` (the phone-minted session reference, E62-08 scenarios need it to
/// craft stale-reference input).
enum HarnessMediaTickets {
    private static let boundConnections = Mutex<[any ByteStreamConnection]>([])

    /// Cancels every media connection the acceptor has bound so far (E62-08 `MIRRORSTOP`: the phone
    /// observes its mirror's media connection ending, as when the Mac mirror window closes).
    static func closeBoundConnections() -> Int {
        let closing = boundConnections.withLock { connections in
            defer { connections = [] }
            return connections
        }
        closing.forEach { $0.cancel() }
        return closing.count
    }

    struct Wiring {
        let acceptor: MediaConnectionAcceptor
        let host: SessionServiceHost
    }

    static func makeIfRequested() -> Wiring? {
        guard UserDefaults.standard.bool(forKey: "HarnessMediaTickets") else { return nil }
        let clock = ContinuousClock()
        let table = MediaTicketTable(clock: clock)
        let issuer = MediaTicketIssuer(table: table, source: SystemMediaTicketSource(), dateProvider: { Date() })
        let registry = MediaSessionRegistry(issuer: issuer)
        let acceptor = MediaConnectionAcceptor(
            validator: MediaTicketValidatorAdapter(validator: MediaTicketValidator(table: table)),
            clock: clock,
            onBound: { binding in
                print("harness-mirror-session: \(binding.mirrorSessionId.map { String(format: "%02x", $0) }.joined())")
                fflush(stdout)
                boundConnections.withLock { $0.append(binding.connection) }
                Task {
                    await registry.bind(
                        binding.connection,
                        to: MediaSessionID(rawValue: binding.sessionID),
                        mirrorSessionId: binding.mirrorSessionId,
                        presentedBy: binding.peer
                    )
                }
            }
        )
        let events = acceptor.events
        Task {
            for await event in events {
                print("harness-media-event: \(event.logDescription)")
                fflush(stdout)
            }
        }
        return Wiring(
            acceptor: acceptor,
            host: SessionServiceHost(services: [MirrorSessionService(registry: registry)])
        )
    }
}

extension HarnessHooks {
    /// The harness's ``NWListenerFactory``: the E15-22 wiring, plus the media acceptor and the
    /// ticket-issuing session service when `-HarnessMediaTickets YES` is set.
    static func makeListenerFactory(
        sessionRegistry: any ControlSessionRegistering,
        decisionCorrelator: PeerDecisionCorrelator,
        pairingCandidateDriver: (any PairingCandidateDriver)?,
        trustStore: TrustStore
    ) -> NWListenerFactory {
        let media = HarnessMediaTickets.makeIfRequested()
        var registered: NWListenerFactory.SessionRegisteredHandler?
        var ended: NWListenerFactory.SessionRegisteredHandler?
        if let host = media?.host {
            registered = { peer, session in host.sessionRegistered(peer: peer, session: session) }
            ended = { peer, session in host.sessionEnded(peer: peer, session: session) }
        }
        return NWListenerFactory(
            sessionRegistry: sessionRegistry,
            decisionCorrelator: decisionCorrelator,
            pairingCandidateDriver: pairingCandidateDriver,
            trustStore: trustStore,
            onSessionRegistered: registered,
            onSessionEnded: ended,
            mediaConnectionHandler: media?.acceptor
        )
    }
}
#endif
