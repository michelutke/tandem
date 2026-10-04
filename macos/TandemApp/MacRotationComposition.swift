import Foundation
import Synchronization
import TandemCrypto
import TandemDevices
import TandemStore
import TandemTransport

/// Late-bound handle on the running listener so a completed rotation can restart it on the new key.
final class ListenerControlBox: Sendable {
    private let control = Mutex<ProductionListenerControl?>(nil)

    func set(_ listenerControl: ProductionListenerControl) {
        control.withLock { $0 = listenerControl }
    }

    func restart() {
        guard let listenerControl = control.withLock({ $0 }) else { return }
        Task {
            await listenerControl.stop()
            try? await listenerControl.start()
        }
    }
}

/// Production composition of Mac-initiated key rotation (E70-16): the one ``MacKeyRotation`` shared
/// by the Key settings tab and the scheduler, whose interval defaults to 365 days (Q18) and is read
/// from `UserDefaults`.
enum MacRotationComposition {
    static let intervalDaysKey = "keyRotationIntervalDays"
    static let defaultIntervalDays = 365

    static func make(
        keychainStore: any KeychainStore,
        trustStore: TrustStore,
        window: any PairingWindowState,
        identityBootstrapper: IdentityBootstrapper,
        listenerControl: ListenerControlBox
    ) -> MacKeyRotation {
        let storedDays = UserDefaults.standard.integer(forKey: intervalDaysKey)
        let days = storedDays > 0 ? storedDays : defaultIntervalDays
        return MacKeyRotation(
            keychainStore: keychainStore,
            trustStore: trustStore,
            window: window,
            dateProvider: { Date() },
            interval: .seconds(days * 86_400),
            dueDateURL: dueDateURL(),
            onSwitched: {
                identityBootstrapper.bootstrapIdentity()
                listenerControl.restart()
            }
        )
    }

    @MainActor
    static func makeViewModel(rotation: MacKeyRotation) -> MacRotationSettingsViewModel? {
        guard let fingerprint = displayFingerprint(of: rotation) else { return nil }
        let viewModel = MacRotationSettingsViewModel(
            rotator: ProductionMacKeyRotator(rotation: rotation),
            currentFingerprint: fingerprint,
            hasAuthenticatedSession: rotation.hasAuthenticatedSession,
            dateProvider: { Date() }
        )
        rotation.observeAuthenticated { connected in
            Task { @MainActor in viewModel.hasAuthenticatedSession = connected }
        }
        return viewModel
    }

    fileprivate static func displayFingerprint(of rotation: MacKeyRotation) -> String? {
        guard let spkiDer = try? rotation.activeSpkiDer(),
              let fingerprint = try? SpkiFingerprint.of(spkiDer: spkiDer) else { return nil }
        return fingerprint.bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func dueDateURL() -> URL {
        let directory = (try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Tandem", isDirectory: true)) ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("next-rotation-due")
    }
}

/// The Key tab's ``MacKeyRotator`` over the shared ``MacKeyRotation``.
struct ProductionMacKeyRotator: MacKeyRotator {
    let rotation: MacKeyRotation

    func rotate() async -> MacKeyRotationResult {
        switch await rotation.rotate() {
        case .switched:
            guard let fingerprint = MacRotationComposition.displayFingerprint(of: rotation) else {
                return .failure(reason: "The new key could not be read")
            }
            return .success(newFingerprint: fingerprint)
        case .awaitingPhones:
            return .failure(reason: "Waiting for your phone to confirm the new key")
        case .unavailable:
            return .failure(reason: "Rotation is not available right now")
        }
    }

    func pendingRotation() -> PendingRotation? {
        rotation.pendingRotation().map { PendingRotation(startedAt: $0.startedAt, phoneNames: $0.phoneNames) }
    }

    func finishRotation() async throws {
        try rotation.finish()
    }

    func cancelRotation() async throws {
        try rotation.cancel()
    }
}
