#if DEBUG
import FeatureMirror
import Foundation
import Synchronization
import TandemCrypto
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
        let service: any SessionService
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
        return Wiring(acceptor: acceptor, service: MirrorSessionService(registry: registry))
    }
}

/// Debug-only E70-09 hook behind `-HarnessMacRotation YES`: the production ``MacKeyRotation`` (E70-16)
/// over the harness keychain and trust store, with a Mac-initiated rotation begun at launch, so every
/// seeded phone is offered the pending key as it connects (`KeyRotation` after its `RotationChallenge`).
/// Prints `harness-mac-rotation: <outcome>` once begun and `harness-mac-rotation-switched` when every
/// phone acked and the identity switched; never any key material (the pending key reaches a phone only
/// inside that phone's own `KeyRotation`). With `-HarnessMacRotationFinishTrigger <path>` the rotation's
/// clock is virtual: when that file appears it is deleted, the clock jumps 7 days forward (no sleeping)
/// and ``MacKeyRotation/finish()`` runs, printing `harness-mac-rotation-finished` or
/// `harness-mac-rotation-finish-failed: <error>`.
enum HarnessMacRotation {
    private final class VirtualClock: @unchecked Sendable {
        private let lock = NSLock()
        private var offset: TimeInterval = 0

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            return Date().addingTimeInterval(offset)
        }

        func advance(by interval: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            offset += interval
        }
    }

    static func makeIfRequested(
        keychainStore: any KeychainStore,
        trustStore: TrustStore,
        window: any PairingWindowState
    ) -> MacKeyRotation? {
        guard UserDefaults.standard.bool(forKey: "HarnessMacRotation") else { return nil }
        let dueDateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-harness-next-rotation-due-\(UUID().uuidString)")
        let clock = VirtualClock()
        let rotation = MacKeyRotation(
            keychainStore: keychainStore,
            trustStore: trustStore,
            window: window,
            dateProvider: { clock.now() },
            interval: .seconds(365 * 86_400),
            dueDateURL: dueDateURL,
            onSwitched: {
                print("harness-mac-rotation-switched")
                fflush(stdout)
            }
        )
        rotation.resume()
        Task {
            let outcome = await rotation.rotate()
            print("harness-mac-rotation: \(outcome)")
            fflush(stdout)
        }
        if let triggerPath = UserDefaults.standard.string(forKey: "HarnessMacRotationFinishTrigger") {
            watchFinishTrigger(path: triggerPath, rotation: rotation, clock: clock)
        }
        return rotation
    }

    private static func watchFinishTrigger(path: String, rotation: MacKeyRotation, clock: VirtualClock) {
        Task.detached {
            while !FileManager.default.fileExists(atPath: path) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? FileManager.default.removeItem(atPath: path)
            clock.advance(by: TrustStore.gracePinLifetime)
            do {
                try rotation.finish()
                print("harness-mac-rotation-finished")
            } catch {
                print("harness-mac-rotation-finish-failed: \(error)")
            }
            fflush(stdout)
        }
    }
}

extension HarnessHooks {
    /// The harness's ``NWListenerFactory``: the E15-22 wiring, plus the media acceptor and the
    /// ticket-issuing session service when `-HarnessMediaTickets YES` is set.
    static func makeListenerFactory(
        sessionRegistry: any ControlSessionRegistering,
        decisionCorrelator: PeerDecisionCorrelator,
        pairingCandidateDriver: (any PairingCandidateDriver)?,
        trustStore: TrustStore,
        window: any PairingWindowState,
        rotation: MacKeyRotation?
    ) -> NWListenerFactory {
        let media = HarnessMediaTickets.makeIfRequested()
        var services: [any SessionService] = []
        if let service = media?.service { services.append(service) }
        if let rotation { services.append(rotation) }
        var registered: NWListenerFactory.SessionRegisteredHandler?
        var ended: NWListenerFactory.SessionRegisteredHandler?
        if !services.isEmpty {
            let host = SessionServiceHost(services: services)
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
            mediaConnectionHandler: media?.acceptor,
            rotation: RotationReceiverConfiguration(window: window, dateProvider: { Date() })
        )
    }
}
#endif
