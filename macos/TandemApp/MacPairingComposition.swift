import AppKit
import Foundation
import Network
import Security
import SwiftUI
import TandemCrypto
import TandemDesign
import TandemPairing
import TandemProtocol
import TandemStore
import TandemTransport

/// The production "Add phone" wiring (E22-14): one ``PairingWindowHost`` the listener is built
/// against at launch, whose window only exists once the owner opens it via ``MacPairingPresenter``.
/// Mirrors the DEBUG-only harness pairing path (`HarnessHooks`) against the same
/// ``TandemPairing/PairingCoordinator``, but with the owner-facing confirmation instead of an
/// auto-confirm hook, and no logging of the secret, QR or confirmation code (invariant 7).
final class MacPairingComposition: @unchecked Sendable {
    enum OpenFailure: Error {
        case identityUnavailable
        case listenerNotReady
    }

    let host: PairingWindowHost
    private let state: PairingCompositionState

    init(
        identityBootstrapper: IdentityBootstrapper,
        trustStore: TrustStore,
        sessionRegistry: any ControlSessionRegistering,
        purgeRegistry: PeerDataPurgeRegistry? = nil,
        onPeerUnpaired: (@Sendable () async -> Void)? = nil,
        onPeerPaired: @escaping @Sendable () -> Void = {}
    ) {
        let state = PairingCompositionState()
        self.state = state
        host = PairingWindowHost {
            guard let currentSpkiDer = Self.macSpkiDer(identityBootstrapper) else {
                throw OpenFailure.identityUnavailable
            }
            guard let port = state.portSource.port else { throw OpenFailure.listenerNotReady }
            let fingerprint = try SpkiFingerprint.of(spkiDer: currentSpkiDer)
            let generation = state.generation.next()
            let macSpkiDer: @Sendable () -> Data = { Self.macSpkiDer(identityBootstrapper) ?? currentSpkiDer }
            return PairingCoordinator(
                fingerprint: fingerprint,
                macSpkiDerProvider: macSpkiDer,
                port: port,
                name: Host.current().localizedName ?? "Mac",
                trustStore: trustStore,
                dateProvider: { Date() },
                sessionRegistry: sessionRegistry,
                regeneratesOnExpiry: false,
                onConfirmationPending: { _, viewModel in state.deliverConfirmation(viewModel, generation: generation) },
                purgeRegistry: purgeRegistry,
                onPeerUnpaired: onPeerUnpaired,
                onPeerPaired: onPeerPaired
            )
        }
    }

    var generation: PairingWindowGeneration { state.generation }

    /// Called for the first listener and again for every restart, so the QR always carries the current port.
    func listenerStarted(_ listener: NWListener) {
        state.portSource.listenerReplaced { listener.port.map { Int($0.rawValue) } }
    }

    func onConfirmation(_ handler: @escaping @Sendable (PairConfirmationViewModel, Int) -> Void) {
        state.confirmationHandler = handler
    }

    static func macSpkiDer(_ identityBootstrapper: IdentityBootstrapper) -> Data? {
        guard case .ready(let identity) = identityBootstrapper.identityState else { return nil }
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            return nil
        }
        let certificateDER = SecCertificateCopyData(certificate) as Data
        return try? LeafSpkiExtractor.subjectPublicKeyInfoDER(certificateDER: certificateDER)
    }
}

private final class PairingCompositionState: @unchecked Sendable {
    let portSource = ListenerPortSource()
    let generation = PairingWindowGeneration()
    private let lock = NSLock()
    private var storedHandler: (@Sendable (PairConfirmationViewModel, Int) -> Void)?

    var confirmationHandler: (@Sendable (PairConfirmationViewModel, Int) -> Void)? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    func deliverConfirmation(_ viewModel: PairConfirmationViewModel, generation: Int) {
        confirmationHandler?(viewModel, generation)
    }
}

/// Opens the pairing window on "Pair phone…", swaps its QR for the confirmation dialog once a
/// candidate's proof verifies, then for the "Paired." screen once trust is committed, and closes it
/// once the host's window is cancelled or declined. Expiry and exhausted attempts keep it open on
/// their own screens. The owner closing it declines a pending confirmation, else cancels.
@MainActor
final class MacPairingPresenter: NSObject, NSWindowDelegate {
    private let composition: MacPairingComposition
    private let clock: any Clock<Duration>
    private var windowController: PairingWindowController?
    private var watchTask: Task<Void, Never>?
    private var pendingConfirmation: PairConfirmationViewModel?
    private var isShowingPaired = false

    init(composition: MacPairingComposition, clock: any Clock<Duration> = ContinuousClock()) {
        self.composition = composition
        self.clock = clock
        super.init()
        composition.onConfirmation { [weak self] viewModel, generation in
            Task { @MainActor in self?.showConfirmation(viewModel, generation: generation) }
        }
    }

    func openPairingWindow() {
        openWindow(manual: false)
    }

    /// "Pair without camera": opens a manual-mode window (ADR-008) the phone enters by address.
    func openManualPairingWindow() {
        openWindow(manual: true)
    }

    private func openWindow(manual: Bool) {
        if let pending = pendingConfirmation, !pending.isResolved {
            Task { await pending.ownerDidDismiss() }
        }
        guard let coordinator = try? (manual ? composition.host.openManual() : composition.host.open()) else {
            _ = GlassDialog.runModal(
                title: "Pairing unavailable.",
                actions: [GlassDialogAction("OK", kind: .primary, isSafeDefault: true)]
            )
            return
        }
        let controller = PairingWindowController(viewModel: coordinator.viewModel)
        controller.window?.delegate = self
        windowController?.window?.delegate = nil
        windowController?.close()
        windowController = controller
        pendingConfirmation = nil
        isShowingPaired = false
        NSApp.activate()
        controller.showWindow(nil)
        watchWindow()
    }

    func windowWillClose(_ notification: Notification) {
        let host = composition.host
        let pending = pendingConfirmation
        watchTask?.cancel()
        windowController = nil
        pendingConfirmation = nil
        Task { await PairingOwnerClose.handle(pending: pending, host: host) }
    }

    private func showConfirmation(_ viewModel: PairConfirmationViewModel, generation: Int) {
        guard composition.generation.isCurrent(generation) else { return }
        pendingConfirmation = viewModel
        windowController?.window?.contentViewController = NSHostingController(
            rootView: PairConfirmationView(viewModel: viewModel, onPaired: { [weak self] in
                Task { @MainActor in self?.showPaired() }
            })
        )
    }

    private func showPaired() {
        guard !isShowingPaired, let pending = pendingConfirmation, pending.isResolved, !pending.didFailToPair else {
            return
        }
        isShowingPaired = true
        windowController?.window?.contentViewController = NSHostingController(
            rootView: PairedView(stateText: pending.pairedStateText, onDone: { [weak self] in
                self?.windowController?.close()
            })
        )
    }

    private func watchWindow() {
        watchTask?.cancel()
        watchTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let closedReason = self.composition.host.coordinator?.window.closedReason
                if closedReason == .paired { self.showPaired() }
                let showingConfirmation = self.pendingConfirmation != nil
                if PairingWindowAutoClose.shouldClose(
                    closedReason: closedReason, showingConfirmation: showingConfirmation
                ) {
                    self.windowController?.close()
                    return
                }
            }
        }
    }
}

extension AppComposition {
    static func makeBonjour(_ identityBootstrapper: IdentityBootstrapper) -> ListenerBonjour {
        ListenerBonjour(
            publisher: NetServiceBonjourPublisher(),
            macSpkiFingerprint: {
                MacPairingComposition.macSpkiDer(identityBootstrapper)
                    .flatMap { try? SpkiFingerprint.of(spkiDer: $0) }
                    .map { Data($0.bytes) }
            },
            dateProvider: { Date() }
        )
    }

    static func makeListenerStarted(
        pairing: MacPairingComposition,
        bonjour: ListenerBonjour,
        onBound: @escaping @Sendable () -> Void
    ) -> @Sendable (ListenerController.StartedListener) async -> Void {
        { started in
            pairing.listenerStarted(started.listener)
            guard let port = started.listener.port?.rawValue else {
                await bonjour.listenerStopped()
                return
            }
            await bonjour.listenerStarted(port: port)
            onBound()
        }
    }

    /// Every ``RetainedLifecycle`` field that comes from the started listener itself (sleep/wake,
    /// network-path-change) rather than from identity/trust-store setup -- split out purely to keep
    /// ``startListener()`` under this repo's `function_body_length` lint budget.
    struct LifecycleControllers {
        let listenerControl: ProductionListenerControl
        let powerEvents: WorkspacePowerEvents
        let pathSource: NWPathMonitorSource
        let sleepWakeController: SleepWakeController
        let pathChangeController: PathChangeController
    }

    /// What the production listener does around every start and stop, and how a failed restart is
    /// reported.
    struct ListenerHooks {
        let started: @Sendable (ListenerController.StartedListener) async -> Void
        let stopped: @Sendable () async -> Void
        let failed: @Sendable (ListenerFailureReason) -> Void
    }

    static func makeListenerHooks(
        pairing: MacPairingComposition,
        identityBootstrapper: IdentityBootstrapper,
        onFailure: @escaping @Sendable (ListenerFailureReason) -> Void,
        onRecovery: @escaping @Sendable () -> Void
    ) -> ListenerHooks {
        let bonjour = makeBonjour(identityBootstrapper)
        return ListenerHooks(
            started: makeListenerStarted(pairing: pairing, bonjour: bonjour, onBound: onRecovery),
            stopped: { await bonjour.listenerStopped() },
            failed: onFailure
        )
    }

    static func makeLifecycleControllers(
        controller: ListenerController,
        started: ListenerController.StartedListener,
        hooks: ListenerHooks,
        controlBox: ListenerControlBox
    ) -> LifecycleControllers {
        let listenerControl = ProductionListenerControl(
            listenerController: controller,
            initiallyStarted: started,
            onStarted: hooks.started,
            onStopped: hooks.stopped
        )
        let powerEvents = WorkspacePowerEvents(notificationCenter: NSWorkspace.shared.notificationCenter)
        let onFailure: @Sendable (any Error) -> Void = { hooks.failed(.classify(listenerError: $0)) }
        let sleepWakeController = SleepWakeController(
            powerEvents: powerEvents, listenerControl: listenerControl, onFailure: onFailure
        )
        let pathSource = NWPathMonitorSource()
        let pathChangeController = PathChangeController(
            pathSource: pathSource, listenerControl: listenerControl, onFailure: onFailure
        )
        controlBox.set(listenerControl, onFailure: onFailure)
        Task {
            await hooks.started(started)
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

    /// Rebinds the running listener for the Retry button after a runtime failure; the failure
    /// reason, or `nil` when it is running again.
    @MainActor static func restartListener(_ lifecycle: RetainedLifecycle) async -> ListenerFailureReason? {
        do {
            try await lifecycle.listenerControl.restart()
            return nil
        } catch {
            return ListenerFailureReason.classify(listenerError: error)
        }
    }
}
