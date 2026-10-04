import AppKit
import Foundation
import Network
import Security
import SwiftUI
import TandemCrypto
import TandemPairing
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
        sessionRegistry: any ControlSessionRegistering
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
            let macSpkiDer = { Self.macSpkiDer(identityBootstrapper) ?? currentSpkiDer }
            return PairingCoordinator(
                fingerprint: fingerprint,
                macSpkiDerProvider: macSpkiDer,
                port: port,
                name: Host.current().localizedName ?? "Mac",
                trustStore: trustStore,
                dateProvider: { Date() },
                sessionRegistry: sessionRegistry,
                regeneratesOnExpiry: false,
                onConfirmationPending: { _, viewModel in state.deliverConfirmation(viewModel, generation: generation) }
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

    private static func macSpkiDer(_ identityBootstrapper: IdentityBootstrapper) -> Data? {
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
/// candidate's proof verifies, and closes it once the host's window is paired, cancelled, expired
/// or declined. The owner closing it declines a pending confirmation, else cancels.
@MainActor
final class MacPairingPresenter: NSObject, NSWindowDelegate {
    private let composition: MacPairingComposition
    private let clock: any Clock<Duration>
    private var windowController: PairingWindowController?
    private var watchTask: Task<Void, Never>?
    private var pendingConfirmation: PairConfirmationViewModel?

    init(composition: MacPairingComposition, clock: any Clock<Duration> = ContinuousClock()) {
        self.composition = composition
        self.clock = clock
        super.init()
        composition.onConfirmation { [weak self] viewModel, generation in
            Task { @MainActor in self?.showConfirmation(viewModel, generation: generation) }
        }
    }

    func openPairingWindow() {
        guard let coordinator = try? composition.host.open() else {
            let alert = NSAlert()
            alert.messageText = "Pairing unavailable."
            alert.runModal()
            return
        }
        let controller = PairingWindowController(viewModel: coordinator.viewModel)
        controller.window?.delegate = self
        windowController?.window?.delegate = nil
        windowController?.close()
        windowController = controller
        pendingConfirmation = nil
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
            rootView: PairConfirmationView(viewModel: viewModel)
        )
    }

    private func watchWindow() {
        watchTask?.cancel()
        watchTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let closedReason = self.composition.host.coordinator?.window.closedReason
                if PairingWindowAutoClose.shouldClose(closedReason: closedReason) {
                    self.windowController?.close()
                    return
                }
            }
        }
    }
}
