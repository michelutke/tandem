#if DEBUG
import Foundation
import Security
import TandemCrypto
import TandemPairing
import TandemProtocol
import TandemStore
import TandemTransport

/// The `-HarnessOpenPairingWindow` wiring, split out of `HarnessHooks.swift` purely to keep that
/// file under this repo's `type_body_length` lint budget.
extension HarnessHooks {
    /// Resolves the `PairingWindowState`/`PairingCandidateDriver` pair `startListenerIfRequested()`
    /// wires into the listener: a real, QR-printing ``TandemPairing/PairingCoordinator`` if
    /// `-HarnessOpenPairingWindow YES` was passed, else the harness's usual
    /// ``NeverOpenPairingWindow``.
    static func resolvePairingWindow(
        identity: SecIdentity,
        keychainStore: any KeychainStore,
        rawPort: UInt16,
        sessionRegistry: any ControlSessionRegistering
    ) -> (window: any PairingWindowState, driver: (any PairingCandidateDriver)?) {
        guard UserDefaults.standard.bool(forKey: "HarnessOpenPairingWindow") else {
            return (NeverOpenPairingWindow(), nil)
        }
        let coordinator = makePairingCoordinator(
            identity: identity,
            keychainStore: keychainStore,
            port: Int(rawPort),
            autoConfirm: UserDefaults.standard.bool(forKey: "HarnessAutoConfirmPairing"),
            sessionRegistry: sessionRegistry
        )
        print("harness-pairing-qr-uri: \(coordinator.viewModel.currentPayload.uri)")
        fflush(stdout)
        retainedPairingCoordinator = coordinator
        return (coordinator.window, coordinator)
    }

    /// Builds the real ``TandemPairing/PairingCoordinator`` `-HarnessOpenPairingWindow` opens,
    /// printing the confirmation code (and, with `autoConfirm`, auto-accepting) the moment a
    /// candidate's proof verifies.
    static func makePairingCoordinator(
        identity: SecIdentity,
        keychainStore: any KeychainStore,
        port: Int,
        autoConfirm: Bool,
        sessionRegistry: any ControlSessionRegistering
    ) -> PairingCoordinator {
        guard let macSpkiDer = spkiDer(for: identity),
              let fingerprint = try? SpkiFingerprint.of(spkiDer: macSpkiDer) else {
            fatalError("-HarnessOpenPairingWindow requested but the harness identity's SPKI could not be read")
        }
        return PairingCoordinator(
            fingerprint: fingerprint,
            macSpkiDerProvider: { macSpkiDer },
            port: port,
            name: "Tandem Harness",
            trustStore: TrustStore(keychainStore: keychainStore),
            dateProvider: { Date() },
            sessionRegistry: sessionRegistry,
            onConfirmationPending: { code, viewModel in
                print("harness-pairing-confirmation-code: \(code)")
                fflush(stdout)
                if autoConfirm {
                    Task { await viewModel.pair() }
                }
            }
        )
    }

    /// Keeps the `-HarnessOpenPairingWindow` coordinator (and the `PairConfirmationViewModel`s it
    /// hands to `onConfirmationPending`) alive for the process lifetime, the same way
    /// `retainedListener` does for the `NWListener` itself.
    nonisolated(unsafe) static var retainedPairingCoordinator: PairingCoordinator?
}
#endif
