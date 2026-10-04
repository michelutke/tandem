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
            guard let port = state.port else { throw OpenFailure.listenerNotReady }
            let fingerprint = try SpkiFingerprint.of(spkiDer: currentSpkiDer)
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
                onConfirmationPending: { _, viewModel in state.deliverConfirmation(viewModel) }
            )
        }
    }

    func listenerStarted(_ listener: NWListener) {
        state.listener = listener
    }

    func onConfirmation(_ handler: @escaping @Sendable (PairConfirmationViewModel) -> Void) {
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
    private let lock = NSLock()
    private var storedListener: NWListener?
    private var storedHandler: (@Sendable (PairConfirmationViewModel) -> Void)?

    var listener: NWListener? {
        get { lock.withLock { storedListener } }
        set { lock.withLock { storedListener = newValue } }
    }

    /// `nil` until the listener has bound -- `NWListener.port` is unset before `.ready`.
    var port: Int? {
        listener?.port.map { Int($0.rawValue) }
    }

    var confirmationHandler: (@Sendable (PairConfirmationViewModel) -> Void)? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    func deliverConfirmation(_ viewModel: PairConfirmationViewModel) {
        confirmationHandler?(viewModel)
    }
}

/// Opens the pairing window on "Pair phone…", swaps its QR for the confirmation dialog once a
/// candidate's proof verifies, and closes it as soon as the host's window is no longer open
/// (success, timeout or cancel) or the owner closes it themselves (cancel).
@MainActor
final class MacPairingPresenter: NSObject, NSWindowDelegate {
    private let composition: MacPairingComposition
    private let clock: any Clock<Duration>
    private var windowController: PairingWindowController?
    private var watchTask: Task<Void, Never>?

    init(composition: MacPairingComposition, clock: any Clock<Duration> = ContinuousClock()) {
        self.composition = composition
        self.clock = clock
        super.init()
        composition.onConfirmation { [weak self] viewModel in
            Task { @MainActor in self?.showConfirmation(viewModel) }
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
        NSApp.activate()
        controller.showWindow(nil)
        watchWindow()
    }

    func windowWillClose(_ notification: Notification) {
        composition.host.cancel()
        watchTask?.cancel()
        windowController = nil
    }

    private func showConfirmation(_ viewModel: PairConfirmationViewModel) {
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
                if !self.composition.host.isOpen {
                    self.windowController?.close()
                    return
                }
            }
        }
    }
}
