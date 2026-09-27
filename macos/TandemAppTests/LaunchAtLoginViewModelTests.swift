import Testing

@testable import TandemApp

/// E22-03 tdd (unit): ``LaunchAtLoginViewModel`` over a scriptable fake ``LoginItemService`` and
/// ``LaunchAtLoginPreferenceStore``, mirroring ``MenuBarViewModelTests``'s own conventions.
@Suite("LaunchAtLoginViewModel")
struct LaunchAtLoginViewModelTests {
    // MARK: - launchAtLoginViewModel_toggleOn_callsRegisterOnce

    @Test @MainActor
    func launchAtLoginViewModel_toggleOn_callsRegisterOnce() {
        let service = FakeLoginItemService(status: .notRegistered)
        let viewModel = LaunchAtLoginViewModel(
            service: service,
            preferenceStore: FakeLaunchAtLoginPreferenceStore()
        )

        viewModel.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(service.unregisterCallCount == 0)
    }

    // MARK: - launchAtLoginViewModel_toggleOff_callsUnregisterOnce

    @Test @MainActor
    func launchAtLoginViewModel_toggleOff_callsUnregisterOnce() {
        let service = FakeLoginItemService(status: .enabled)
        let viewModel = LaunchAtLoginViewModel(
            service: service,
            preferenceStore: FakeLaunchAtLoginPreferenceStore()
        )

        viewModel.setEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(service.registerCallCount == 0)
    }

    // MARK: - launchAtLoginViewModel_firstPairingNeverToggled_registersByDefault

    @Test @MainActor
    func launchAtLoginViewModel_firstPairingNeverToggled_registersByDefault() {
        let service = FakeLoginItemService(status: .notRegistered)
        let preferenceStore = FakeLaunchAtLoginPreferenceStore()
        let viewModel = LaunchAtLoginViewModel(service: service, preferenceStore: preferenceStore)

        viewModel.handleSuccessfulPairing()

        #expect(service.registerCallCount == 1)
        #expect(preferenceStore.hasUserSetToggle)

        // A later pairing must not re-register once the toggle is considered set (either by the
        // user or, as here, by this same default having already fired once).
        viewModel.handleSuccessfulPairing()
        #expect(service.registerCallCount == 1)
    }

    // MARK: - launchAtLoginViewModel_statusChangedExternally_toggleReflectsStatusOnActivate

    @Test @MainActor
    func launchAtLoginViewModel_statusChangedExternally_toggleReflectsStatusOnActivate() {
        let service = FakeLoginItemService(status: .enabled)
        let viewModel = LaunchAtLoginViewModel(
            service: service,
            preferenceStore: FakeLaunchAtLoginPreferenceStore()
        )
        #expect(viewModel.isEnabled)

        // Changed outside the app (e.g. the user disabled it from System Settings directly).
        service.currentStatus = .notRegistered
        viewModel.refreshStatus()

        #expect(!viewModel.isEnabled)
    }

    // MARK: - launchAtLoginViewModel_statusRequiresApproval_showsApprovalHint

    @Test @MainActor
    func launchAtLoginViewModel_statusRequiresApproval_showsApprovalHint() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let viewModel = LaunchAtLoginViewModel(
            service: service,
            preferenceStore: FakeLaunchAtLoginPreferenceStore()
        )

        #expect(viewModel.approvalHintText == "Approve Tandem in System Settings > General > Login Items.")
    }
}

/// Scriptable fake ``LoginItemService``: records call counts and lets tests drive ``status()``
/// directly, including simulating a status change made outside the app.
private final class FakeLoginItemService: LoginItemService {
    var currentStatus: LoginItemStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LoginItemStatus) {
        self.currentStatus = status
    }

    func register() throws {
        registerCallCount += 1
        currentStatus = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        currentStatus = .notRegistered
    }

    func status() -> LoginItemStatus {
        currentStatus
    }
}

/// Fake ``LaunchAtLoginPreferenceStore``: an in-memory `Bool`, no `UserDefaults` involved.
private final class FakeLaunchAtLoginPreferenceStore: LaunchAtLoginPreferenceStore {
    var hasUserSetToggle = false
}
