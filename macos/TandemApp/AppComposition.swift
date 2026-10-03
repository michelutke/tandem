import AppKit
import Network
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTransport

/// Starts the real mTLS listener and its lifecycle controllers for an ordinary launch, Debug or
/// Release alike (E20-10, E20-11; E22-01's own follow-up: "Lifecycle wired only in DEBUG
/// HarnessHooks; production listener startup"). ``HarnessHooks/startListenerIfRequested()`` stays
/// the one place the E15-22 CI harness itself runs the listener (a fixed `-HarnessListenerPort`,
/// against the harness keychain); this is what every other launch actually runs, on an
/// OS-assigned port, against whichever `KeychainStoreFactory` selects.
///
/// No pairing window is wired into the app yet (E14 pairing UI lands separately): exactly like
/// the harness's own `NeverOpenPairingWindow`, ``NoPairingWindow`` never admits a candidate, so
/// this fails closed (invariant 5) -- only a peer whose SPKI fingerprint is already in
/// ``TrustStore`` is ever admitted until pairing UI replaces this stub.
enum AppComposition {
    /// Everything ``startListener()`` wires up, kept alive for the process lifetime by whoever
    /// calls it.
    struct RetainedLifecycle {
        let listener: NWListener
        let listenerControl: ProductionListenerControl
        let powerEvents: WorkspacePowerEvents
        let pathSource: NWPathMonitorSource
        let sleepWakeController: SleepWakeController
        let pathChangeController: PathChangeController
        /// The exact ``TandemProtocol/ControlSessionRegistry`` the running listener registers
        /// every `.trusted` session into (E14-26): shared, not re-created, so a later Devices-
        /// screen unpair (``AppComposition/makeUnpairAction(trustStore:sessionRegistry:purgeRegistry:)``)
        /// can find the same live session `NWListenerFactory` already tracks, rather than a second,
        /// empty registry that would always see "not connected".
        let sessionRegistry: ControlSessionRegistry
        /// The exact ``TandemStore/TrustStore`` the running listener's verify block and `CONTROL`
        /// revoke consumer both read/write (E14-26) -- shared for the same reason as
        /// ``sessionRegistry``.
        let trustStore: TrustStore
        /// Empty until a later-phase store registers a purger (``TandemStore/PeerDataPurgeRegistry``'s
        /// own kdoc, E50-09/E51-04); retained here so every unpair -- incoming `Revoke` or an
        /// owner-initiated Devices-screen unpair -- runs against the same registry.
        let purgeRegistry: PeerDataPurgeRegistry
        /// The currently-paired peer's real ``ConnectionStateMachine/ConnectionState`` stream
        /// (E22-11), forwarded across reconnects by a ``ConnectionStateRelay`` -- `nil` if no peer
        /// is paired at all (``MenuBarViewModel``/``ErrorBannerViewModel`` then show `.notPaired`/no
        /// banner, exactly like their own `stateStream: nil` default already did).
        let makeMenuBarStateStream: (@Sendable () -> AsyncStream<ConnectionStateMachine.ConnectionState>)?
        /// The same peer's display name (``TandemStore/PeerRecord/displayName``), or `nil` alongside
        /// ``makeMenuBarStateStream`` when none is paired.
        let pairedPeerName: String?
    }

    /// Why ``startListener()`` didn't start anything -- surfaced to the menu (never retried
    /// silently), rather than the app looking healthy with no listener and no signal (invariant 5:
    /// closed must also be visible).
    enum StartFailure: Error, Sendable {
        case identityNotReady
        case listenerBindFailed
    }

    /// Bootstraps the identity and, if it's ready, starts the listener and both lifecycle
    /// controllers.
    static func startListener() -> Result<RetainedLifecycle, StartFailure> {
        let keychainStore = KeychainStoreFactory.make()
        let identityBootstrapper = IdentityBootstrapper(keychainStore: keychainStore)
        identityBootstrapper.bootstrapIdentity()

        guard case .ready = identityBootstrapper.identityState else {
            return .failure(.identityNotReady)
        }

        let trustStore = TrustStore(keychainStore: keychainStore)
        let sessionRegistry = ControlSessionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let decisionCorrelator = PeerDecisionCorrelator()
        let pinMismatchBannerGate = PinMismatchBannerGate()
        let verify = verifyBlock(
            trustStore: trustStore,
            decisionCorrelator: decisionCorrelator,
            pinMismatchBannerGate: pinMismatchBannerGate
        )
        let menuBarWiring = makeMenuBarWiring(trustStore: trustStore, sessionRegistry: sessionRegistry)
        let controller = ListenerController(
            identityStateProvider: identityBootstrapper,
            listenerFactory: NWListenerFactory(
                sessionRegistry: sessionRegistry,
                decisionCorrelator: decisionCorrelator,
                trustStore: trustStore,
                onSessionRegistered: menuBarWiring.onSessionRegistered,
                rotation: RotationReceiverConfiguration(window: NoPairingWindow(), dateProvider: { Date() })
            ),
            port: .any,
            verify: verify
        )
        guard let started = try? controller.start() else {
            return .failure(.listenerBindFailed)
        }

        let controllers = makeLifecycleControllers(controller: controller, started: started)
        return .success(
            RetainedLifecycle(
                listener: started.listener,
                listenerControl: controllers.listenerControl,
                powerEvents: controllers.powerEvents,
                pathSource: controllers.pathSource,
                sleepWakeController: controllers.sleepWakeController,
                pathChangeController: controllers.pathChangeController,
                sessionRegistry: sessionRegistry,
                trustStore: trustStore,
                purgeRegistry: purgeRegistry,
                makeMenuBarStateStream: menuBarWiring.makeStream,
                pairedPeerName: menuBarWiring.peerName
            )
        )
    }

    /// Every ``RetainedLifecycle`` field E22-11 adds, split out purely to keep ``startListener()``
    /// under this repo's `function_body_length` lint budget. No pairing UI exists yet (E14) to pair
    /// more than one peer in practice, so the first (only, in practice) paired record is "the
    /// currently paired peer" the menu bar and error banner observe -- a ``ConnectionStateRelay``
    /// keeps forwarding that one peer's real ``ConnectionStateMachine/ConnectionState`` across
    /// reconnects, since `onSessionRegistered` fires again each time a new `TandemSession` reaches
    /// Ready for the same fingerprint.
    private struct MenuBarWiring {
        let makeStream: (@Sendable () -> AsyncStream<ConnectionStateMachine.ConnectionState>)?
        let peerName: String?
        let onSessionRegistered: NWListenerFactory.SessionRegisteredHandler?
    }

    private static func makeMenuBarWiring(
        trustStore: TrustStore,
        sessionRegistry: ControlSessionRegistry
    ) -> MenuBarWiring {
        guard let pairedPeer = (try? trustStore.list())?.first else {
            return MenuBarWiring(makeStream: nil, peerName: nil, onSessionRegistered: nil)
        }
        let relay = ConnectionStateRelay()
        let onSessionRegistered: NWListenerFactory.SessionRegisteredHandler = { fingerprint, session in
            guard fingerprint == pairedPeer.fingerprint else { return }
            Task {
                guard await sessionRegistry.shouldForwardState(of: session, for: fingerprint) else { return }
                await relay.attach(session)
            }
        }
        return MenuBarWiring(
            makeStream: { relay.makeStream() },
            peerName: pairedPeer.displayName,
            onSessionRegistered: onSessionRegistered
        )
    }

    /// Every ``RetainedLifecycle`` field that comes from the started listener itself (sleep/wake,
    /// network-path-change) rather than from identity/trust-store setup -- split out purely to keep
    /// ``startListener()`` under this repo's `function_body_length` lint budget.
    private struct LifecycleControllers {
        let listenerControl: ProductionListenerControl
        let powerEvents: WorkspacePowerEvents
        let pathSource: NWPathMonitorSource
        let sleepWakeController: SleepWakeController
        let pathChangeController: PathChangeController
    }

    private static func makeLifecycleControllers(
        controller: ListenerController,
        started: ListenerController.StartedListener
    ) -> LifecycleControllers {
        let listenerControl = ProductionListenerControl(listenerController: controller, initiallyStarted: started)
        let powerEvents = WorkspacePowerEvents(notificationCenter: NSWorkspace.shared.notificationCenter)
        let sleepWakeController = SleepWakeController(powerEvents: powerEvents, listenerControl: listenerControl)
        let pathSource = NWPathMonitorSource()
        let pathChangeController = PathChangeController(pathSource: pathSource, listenerControl: listenerControl)
        Task {
            await sleepWakeController.start()
            await pathChangeController.start()
        }

        return LifecycleControllers(
            listenerControl: listenerControl,
            powerEvents: powerEvents,
            pathSource: pathSource,
            sleepWakeController: sleepWakeController,
            pathChangeController: pathChangeController
        )
    }

    /// Builds ``startListener()``'s verify block, split out purely to keep that function under this
    /// repo's `function_body_length` lint budget. E12-12/E12-13: correlates `PeerVerifier`'s
    /// `onDecision` hook (the fingerprint it already computed for a connection's own verify
    /// callback) with that same connection's session wiring at `.ready`, so a trusted client's
    /// control session is registered under its real SPKI fingerprint rather than re-deriving it
    /// after the fact -- mirrors `HarnessHooks`. Also feeds every `.rejected` decision into
    /// `pinMismatchBannerGate` (E22-10, `docs/planning/decisions.md` D-59/D-76): a `.rejected`
    /// verify-callback outcome is always pre-pin-check, so it only ever bumps the gate's aggregate
    /// counter -- never a per-connection banner.
    private static func verifyBlock(
        trustStore: TrustStore,
        decisionCorrelator: PeerDecisionCorrelator,
        pinMismatchBannerGate: PinMismatchBannerGate
    ) -> TandemVerifyBlock {
        PeerVerifier.makeVerifyBlock(
            trustStore: TandemTrustStoreReader(trustStore: trustStore, dateProvider: { Date() }),
            window: NoPairingWindow(),
            onDecision: { metadata, decision, fingerprint, spkiDer, candidateToken in
                decisionCorrelator.record(
                    metadataIdentifier: ObjectIdentifier(metadata),
                    decision: decision,
                    fingerprint: fingerprint,
                    spkiDer: spkiDer,
                    candidateToken: candidateToken
                )
                if decision == .rejected {
                    Task { await pinMismatchBannerGate.recordRejection() }
                }
            }
        )
    }
}

/// No pairing window is wired into the app yet (E14 pairing UI lands separately); mirrors the
/// harness's own `NeverOpenPairingWindow` so a first-time candidate is refused rather than
/// silently admitted (invariant 5, fail closed).
private struct NoPairingWindow: PairingWindowState {
    var isOpen: Bool { false }
    func admitCandidate() -> PairingCandidateToken? { nil }
    func releaseCandidate(_ token: PairingCandidateToken) {}
}
