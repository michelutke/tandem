import AppKit
import Network
import TandemCrypto
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

        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: TandemTrustStoreReader(trustStore: TrustStore(keychainStore: keychainStore)),
            window: NoPairingWindow()
        )
        let controller = ListenerController(
            identityStateProvider: identityBootstrapper,
            listenerFactory: NWListenerFactory(),
            port: .any,
            verify: verify
        )
        guard let started = try? controller.start() else {
            return .failure(.listenerBindFailed)
        }

        let listenerControl = ProductionListenerControl(listenerController: controller, initiallyStarted: started)
        let powerEvents = WorkspacePowerEvents(notificationCenter: NSWorkspace.shared.notificationCenter)
        let sleepWakeController = SleepWakeController(powerEvents: powerEvents, listenerControl: listenerControl)
        let pathSource = NWPathMonitorSource()
        let pathChangeController = PathChangeController(pathSource: pathSource, listenerControl: listenerControl)
        Task {
            await sleepWakeController.start()
            await pathChangeController.start()
        }

        return .success(
            RetainedLifecycle(
                listener: started.listener,
                listenerControl: listenerControl,
                powerEvents: powerEvents,
                pathSource: pathSource,
                sleepWakeController: sleepWakeController,
                pathChangeController: pathChangeController
            )
        )
    }
}

/// No pairing window is wired into the app yet (E14 pairing UI lands separately); mirrors the
/// harness's own `NeverOpenPairingWindow` so a first-time candidate is refused rather than
/// silently admitted (invariant 5, fail closed).
private struct NoPairingWindow: PairingWindowState {
    var isOpen: Bool { false }
    func admitCandidate() -> Bool { false }
    func releaseCandidate() {}
}
