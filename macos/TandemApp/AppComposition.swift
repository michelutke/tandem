import AppKit
import FeatureClipboard
import Network
import TandemCrypto
import TandemDesign
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
/// Pairing goes through ``MacPairingComposition``: its ``TandemPairing/PairingWindowHost`` admits
/// a first-time candidate only while the owner has a window open (E22-14), and fails closed
/// (invariant 5) otherwise -- only a peer whose SPKI fingerprint is already in ``TrustStore`` is
/// admitted.
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
        /// The paired peer's real ``ConnectionStateMachine/ConnectionState`` stream (E22-11),
        /// forwarded across reconnects (and across a first pairing made after launch) by a
        /// ``ConnectionStateRelay``.
        let makeMenuBarStateStream: (@Sendable () -> AsyncStream<ConnectionStateMachine.ConnectionState>)?
        /// Like ``makeMenuBarStateStream``, but a Ready from one phone never clears another phone's
        /// fail-closed state, so the trust banner follows the peer that caused it.
        let makeBannerStateStream: (@Sendable () -> AsyncStream<ConnectionStateMachine.ConnectionState>)?
        /// The paired peer's display name, republished on pairing commit and unpair.
        let pairedPeer: PairedPeerState
        /// Feature services attached to every registered session (E22-12).
        let sessionFeatures: SessionFeatures
        /// The user-opened pairing window the listener is wired against (E22-14).
        let pairing: MacPairingComposition
        /// Mirror media acceptor, ticket service, window and request model wiring (E62-12).
        let mirror: MirrorComposition
        /// Mac-initiated key rotation shared by the Key settings tab and the scheduler (E70-16).
        let rotation: MacKeyRotation
    }

    /// Bootstraps the identity and, if it's ready, starts the listener and both lifecycle
    /// controllers.
    static func startListener(
        onRuntimeFailure: @escaping @Sendable (ListenerFailureReason) -> Void,
        onRuntimeRecovery: @escaping @Sendable () -> Void
    ) -> Result<RetainedLifecycle, ListenerStartFailure> {
        let keychainStore = KeychainStoreFactory.make()
        let identityBootstrapper = makeIdentityBootstrapper(keychainStore)

        let core = makeCore(keychainStore: keychainStore, identityBootstrapper: identityBootstrapper)
        if let failure = bootstrapFailure(identityBootstrapper, core: core) { return .failure(failure) }

        let mirror = MirrorComposition()
        let sessionFeatures = makeSessionFeatures(core: core, mirror: mirror)
        let menuBarWiring = makeMenuBarWiring(sessionRegistry: core.sessionRegistry)
        let controller = makeController(
            identityBootstrapper: identityBootstrapper,
            core: core,
            chaining: ListenerChaining(
                features: sessionFeatures,
                onSessionRegistered: menuBarWiring.onSessionRegistered,
                mediaConnectionHandler: mirror.acceptor
            )
        )
        let started: ListenerController.StartedListener
        switch controller.startResult() {
        case .success(let listener): started = listener
        case .failure(let failure): return .failure(failure)
        }

        let controllers = makeLifecycleControllers(
            controller: controller,
            started: started,
            hooks: makeListenerHooks(
                pairing: core.pairing, identityBootstrapper: identityBootstrapper,
                onFailure: onRuntimeFailure, onRecovery: onRuntimeRecovery
            ),
            controlBox: core.listenerControl
        )
        core.rotation.startScheduler()
        return .success(
            RetainedLifecycle(
                listener: started.listener,
                listenerControl: controllers.listenerControl,
                powerEvents: controllers.powerEvents,
                pathSource: controllers.pathSource,
                sleepWakeController: controllers.sleepWakeController,
                pathChangeController: controllers.pathChangeController,
                sessionRegistry: core.sessionRegistry,
                trustStore: core.trustStore,
                purgeRegistry: core.purgeRegistry,
                makeMenuBarStateStream: menuBarWiring.makeStream,
                makeBannerStateStream: menuBarWiring.makeBannerStream,
                pairedPeer: core.pairedPeer,
                sessionFeatures: sessionFeatures,
                pairing: core.pairing,
                mirror: mirror,
                rotation: core.rotation
            )
        )
    }

    /// Bootstraps the identity and republishes the paired phone, which an identity reset may have
    /// removed; the failure to start the listener on it, or `nil` when it is ready.
    private static func bootstrapFailure(_ bootstrapper: IdentityBootstrapper, core: Core) -> ListenerStartFailure? {
        bootstrapper.bootstrapIdentity()
        Task { await core.pairedPeer.refresh() }
        return ListenerStartFailure(identityState: bootstrapper.identityState)
    }

    private static func makeIdentityBootstrapper(_ keychainStore: any KeychainStore) -> IdentityBootstrapper {
        IdentityBootstrapper(keychainStore: keychainStore, onIdentityReset: { IdentityResetNotice.markReset() })
    }

    private static func makeSessionFeatures(core: Core, mirror: MirrorComposition) -> SessionFeatures {
        let features = SessionFeatures.make(
            purgeRegistry: core.purgeRegistry,
            sessionRegistry: core.sessionRegistry,
            mirrorService: mirror.service,
            rotationService: core.rotation
        )
        installClipboardToast(on: features.clipboard, pairedPeer: core.pairedPeer)
        return features
    }

    /// Shows the "Copied from <device>." toast on every clip received from the phone.
    private static func installClipboardToast(on clipboard: ActiveClipboard, pairedPeer: PairedPeerState) {
        let viewModel = MainActor.assumeIsolated {
            let panel = ToastPanelController()
            return ClipboardToastViewModel(
                clock: ContinuousClock(),
                deviceName: { pairedPeer.displayName },
                present: { panel.show(text: $0) }
            )
        }
        clipboard.setReceivedHandler { Task { @MainActor in viewModel.clipboardReceived() } }
    }

    private struct Core {
        let trustStore: TrustStore
        let sessionRegistry: ControlSessionRegistry
        let purgeRegistry: PeerDataPurgeRegistry
        let pairing: MacPairingComposition
        let pairedPeer: PairedPeerState
        let rotation: MacKeyRotation
        let listenerControl: ListenerControlBox
    }

    private static func makeCore(keychainStore: any KeychainStore, identityBootstrapper: IdentityBootstrapper) -> Core {
        let trustStore = TrustStore(keychainStore: keychainStore)
        let sessionRegistry = ControlSessionRegistry()
        let pairedPeer = MainActor.assumeIsolated { PairedPeerState(trustStore: trustStore) }
        let pinnedPeers: @Sendable () throws -> Set<SpkiFingerprint> = { try trustStore.pinnedPeers() }
        let purgeRegistry = PeerDataPurgeRegistry(
            trustedPeers: KeychainStoreFactory.usesHarnessKeychain ? nil : pinnedPeers
        )
        let pairing = MacPairingComposition(
            identityBootstrapper: identityBootstrapper,
            trustStore: trustStore,
            sessionRegistry: sessionRegistry,
            purgeRegistry: purgeRegistry,
            onPeerUnpaired: { await pairedPeer.refresh() },
            onPeerPaired: {
                Task { @MainActor in
                    pairedPeer.refresh()
                    IdentityResetNotice.shared.clear()
                    PeerUnpairedNotice.shared.clear()
                }
            }
        )
        let listenerControl = ListenerControlBox()
        let rotation = MacRotationComposition.make(
            keychainStore: keychainStore,
            trustStore: trustStore,
            window: pairing.host,
            identityBootstrapper: identityBootstrapper,
            listenerControl: listenerControl,
            purgeRegistry: purgeRegistry,
            pairedPeer: pairedPeer
        )
        rotation.resume()
        return Core(
            trustStore: trustStore,
            sessionRegistry: sessionRegistry,
            purgeRegistry: purgeRegistry,
            pairing: pairing,
            pairedPeer: pairedPeer,
            rotation: rotation,
            listenerControl: listenerControl
        )
    }

    private struct ListenerChaining {
        let features: SessionFeatures
        let onSessionRegistered: NWListenerFactory.SessionRegisteredHandler?
        let mediaConnectionHandler: any MediaConnectionHandling
    }

    private static func makeController(
        identityBootstrapper: IdentityBootstrapper,
        core: Core,
        chaining: ListenerChaining
    ) -> ListenerController {
        let (sessionRegistry, trustStore, pairing) = (core.sessionRegistry, core.trustStore, core.pairing)
        let decisionCorrelator = PeerDecisionCorrelator()
        let verify = verifyBlock(
            trustStore: trustStore,
            window: pairing.host,
            decisionCorrelator: decisionCorrelator,
            pinMismatchBannerGate: PinMismatchBannerGate()
        )
        return ListenerController(
            identityStateProvider: identityBootstrapper,
            listenerFactory: NWListenerFactory(
                sessionRegistry: sessionRegistry,
                decisionCorrelator: decisionCorrelator,
                pairingCandidateDriver: pairing.host,
                trustStore: trustStore,
                onSessionRegistered: chaining.features.onSessionRegistered(chaining: chaining.onSessionRegistered),
                onSessionEnded: chaining.features.onSessionEnded,
                mediaConnectionHandler: chaining.mediaConnectionHandler,
                rotation: RotationReceiverConfiguration(window: pairing.host, dateProvider: { Date() }),
                purgeRegistry: core.purgeRegistry,
                onPeerUnpaired: { [pairedPeer = core.pairedPeer] in
                    await MainActor.run { PeerUnpairedNotice.shared.peerUnpaired(name: pairedPeer.displayName) }
                    await pairedPeer.refresh()
                }
            ),
            port: .any,
            verify: verify,
            portStore: UserDefaultsListenerPortStore()
        )
    }

    /// Every ``RetainedLifecycle`` field E22-11 adds, split out purely to keep ``startListener()``
    /// under this repo's `function_body_length` lint budget. A ``ConnectionStateRelay`` forwards
    /// the real ``ConnectionStateMachine/ConnectionState`` of whichever trusted session registers
    /// last (one peer in practice, including a peer first paired after launch), since
    /// `onSessionRegistered` fires again each time a new `TandemSession` reaches Ready.
    private struct MenuBarWiring {
        let makeStream: @Sendable () -> AsyncStream<ConnectionStateMachine.ConnectionState>
        let makeBannerStream: @Sendable () -> AsyncStream<ConnectionStateMachine.ConnectionState>
        let onSessionRegistered: NWListenerFactory.SessionRegisteredHandler
    }

    private static func makeMenuBarWiring(sessionRegistry: ControlSessionRegistry) -> MenuBarWiring {
        let relay = ConnectionStateRelay()
        let bannerRelay = ConnectionStateRelay(isolatesFailuresByPeer: true)
        return MenuBarWiring(
            makeStream: { relay.makeStream() },
            makeBannerStream: { bannerRelay.makeStream() },
            onSessionRegistered: { fingerprint, session in
                Task {
                    guard await sessionRegistry.shouldForwardState(of: session, for: fingerprint) else { return }
                    await relay.attach(session)
                    await bannerRelay.attach(session, peer: fingerprint)
                }
            }
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
        window: any PairingWindowState,
        decisionCorrelator: PeerDecisionCorrelator,
        pinMismatchBannerGate: PinMismatchBannerGate
    ) -> TandemVerifyBlock {
        PeerVerifier.makeVerifyBlock(
            trustStore: TandemTrustStoreReader(trustStore: trustStore, dateProvider: { Date() }),
            window: window,
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
