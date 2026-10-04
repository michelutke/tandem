#if DEBUG
import Foundation
import TandemCrypto
import TandemDevices
import TandemStore

/// DEBUG-only fake `LoginItemService` for the Settings window's `-UITestScenario` window
/// (E22-05, mirrors `ScenarioView`'s own fakes elsewhere in this target): a real `SMAppService`
/// registration would leave the toggle's value at the mercy of an unsigned/CI-unfriendly system
/// call (approval, entitlement) rather than proving the toggle's own value survives a tab switch
/// (E22-05's actual acceptance criterion) -- so a `-UITestScenario` launch wires the Settings
/// window to this scriptable in-memory fake instead of `SMAppServiceLoginItemService`.
final class InMemoryLoginItemService: LoginItemService {
    private var currentStatus: LoginItemStatus = .notRegistered

    func register() throws {
        currentStatus = .enabled
    }

    func unregister() throws {
        currentStatus = .notRegistered
    }

    func status() -> LoginItemStatus {
        currentStatus
    }
}

/// DEBUG-only in-memory `LaunchAtLoginPreferenceStore` for the same reason as
/// ``InMemoryLoginItemService`` -- never touches real `UserDefaults`.
final class InMemoryLaunchAtLoginPreferenceStore: LaunchAtLoginPreferenceStore {
    var hasUserSetToggle = false
}

/// DEBUG-only `MacKeyRotator` for the Settings window's `-UITestScenario` window (E70-11): always
/// succeeds with a fixed new fingerprint, never touches a real key.
struct ScenarioMacKeyRotator: MacKeyRotator {
    static let oldFingerprint = "AA:BB:CC:01"
    static let newFingerprint = "DD:EE:FF:02"

    func rotate() async -> MacKeyRotationResult {
        .success(newFingerprint: Self.newFingerprint)
    }

    func pendingRotation() -> PendingRotation? { nil }

    func finishRotation() async throws {}

    func cancelRotation() async throws {}
}

/// Builds a `TandemDevices.PairedDevicesViewModel` (E14-14) seeded with one paired phone, for the
/// Settings window's `-UITestScenario` window (E22-05) -- over a throwaway on-disk
/// `TandemCrypto.SecItemKeychainStore` (E10-07b), the same `TemporaryFileKeychain` approach
/// `PairedDevicesCompositionTests` already established, rather than `TandemTestSupport`'s
/// `InMemoryKeychainStore`, which isn't linked into this app target (see that test file's own
/// kdoc for the Xcode SwiftPM linking bug this avoids). `unpair` is a no-op: this is a seeded
/// UI-test window, not a real revoke flow -- `PairedDevicesView`'s own row/Revoke-button
/// rendering is all `settingsWindow_pairedDevicesTab_showsSeededRowWithRevokeButton` needs.
enum SettingsScenarioSupport {
    /// Matches `ScenarioView.pairedConnectedPeerName` -- every DEBUG scenario in this target
    /// seeds the same phone name.
    static let seededPeerName = "Pixel 8"

    @MainActor
    static func makePairedDevicesViewModel() -> PairedDevicesViewModel {
        let trustStore = TrustStore(keychainStore: makeTemporaryKeychainStore())
        if let fingerprint = try? SpkiFingerprint(bytes: Data(repeating: 0x22, count: SpkiFingerprint.byteCount)) {
            try? trustStore.put(
                PeerRecord(
                    fingerprint: fingerprint,
                    displayName: seededPeerName,
                    pairedAt: Date(),
                    lastSeen: Date(),
                    capabilities: []
                )
            )
        }
        return PairedDevicesViewModel(trustStore: trustStore, dateProvider: { Date() }, unpair: { _ in })
    }

    @MainActor
    static func makeRotationViewModel() -> MacRotationSettingsViewModel {
        MacRotationSettingsViewModel(
            rotator: ScenarioMacKeyRotator(),
            currentFingerprint: ScenarioMacKeyRotator.oldFingerprint,
            hasAuthenticatedSession: true,
            dateProvider: { Date() }
        )
    }

    private static func makeTemporaryKeychainStore() -> SecItemKeychainStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-settings-scenario-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("scenario.keychain-db").path
        guard let fileKeychain = try? FileKeychain.createOrOpen(path: path, password: UUID().uuidString) else {
            fatalError("SettingsScenarioSupport failed to create a temporary keychain")
        }
        return SecItemKeychainStore(target: .file(fileKeychain))
    }
}
#endif
