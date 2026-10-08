import Foundation
import Testing

@testable import TandemApp
@testable import TandemProtocol

/// E22-09 tdd (unit): mainWindowState_relaunch_restoresSelectedSection, mirroring
/// ``LaunchAtLoginViewModelTests``'s own conventions.
@Suite("MainWindowViewModel")
struct MainWindowViewModelTests {
    // MARK: - mainWindowState_relaunch_restoresSelectedSection

    @Test @MainActor
    func mainWindowState_relaunch_restoresSelectedSection() throws {
        let store = FakeMainWindowSectionStore()
        let viewModel = MainWindowViewModel(deviceName: "Pixel 9", connectionState: .online, sectionStore: store)

        let devicesSection = try #require(MainWindowViewModel.sections.last)
        viewModel.select(devicesSection)
        #expect(viewModel.selectedSectionID == devicesSection.id)

        // Simulates a relaunch: a fresh view model built over the same (now persisted) store.
        let relaunched = MainWindowViewModel(deviceName: "Pixel 9", connectionState: .online, sectionStore: store)
        #expect(relaunched.selectedSectionID == devicesSection.id)
    }

    // MARK: - mainWindowViewModel_noPersistedSelection_defaultsToFirstSection

    @Test @MainActor
    func mainWindowViewModel_noPersistedSelection_defaultsToFirstSection() throws {
        let viewModel = MainWindowViewModel(
            deviceName: "Pixel 9",
            connectionState: .online,
            sectionStore: FakeMainWindowSectionStore()
        )

        let firstSection = try #require(MainWindowViewModel.sections.first)
        #expect(viewModel.selectedSectionID == firstSection.id)
    }

    // MARK: - mainWindowViewModel_offline_connectionStateTextShowsLastSeen

    @Test @MainActor
    func mainWindowViewModel_offline_connectionStateTextShowsLastSeen() throws {
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 30)
        let lastSeen = try #require(Calendar.current.date(from: components))
        let viewModel = MainWindowViewModel(
            deviceName: "Pixel 9",
            connectionState: .offline(lastSeen: lastSeen),
            sectionStore: FakeMainWindowSectionStore()
        )

        #expect(viewModel.isOffline)
        #expect(viewModel.connectionStateText == "Offline · seen 09:30")
    }

    // MARK: - mainWindowViewModel_sectionDisabled_isDisabledReturnsTrue

    @Test @MainActor
    func mainWindowViewModel_sectionDisabled_isDisabledReturnsTrue() {
        let messages = MainWindowViewModel.sections[0]
        let photos = MainWindowViewModel.sections[1]
        let viewModel = MainWindowViewModel(
            deviceName: "Pixel 9",
            connectionState: .online,
            disabledSectionIDs: [messages.id],
            sectionStore: FakeMainWindowSectionStore()
        )

        #expect(viewModel.isDisabled(messages))
        #expect(!viewModel.isDisabled(photos))
    }

    // MARK: - live section state mapping

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private func makeLive(
        connectionState: MainWindowViewModel.ConnectionState = .online,
        isPaired: Bool = true
    ) -> MainWindowViewModel {
        MainWindowViewModel(
            deviceName: "Pixel 9",
            connectionState: connectionState,
            isPaired: isPaired,
            sectionStore: FakeMainWindowSectionStore(),
            now: { Self.fixedNow }
        )
    }

    @Test @MainActor
    func mainWindowViewModel_readyState_isOnlineAndSidebarSaysConnected() {
        let viewModel = makeLive(connectionState: .offline(lastSeen: Date(timeIntervalSince1970: 1)))

        viewModel.apply(.ready)

        #expect(!viewModel.isOffline)
        #expect(viewModel.connectionStateText == "Connected.")
    }

    @Test @MainActor
    func mainWindowViewModel_onlineThenDisconnected_offlineWithLastSeenFromClock() {
        let viewModel = makeLive()

        viewModel.apply(.disconnected(reason: nil))

        #expect(viewModel.connectionState == .offline(lastSeen: Self.fixedNow))
    }

    @Test @MainActor
    func mainWindowViewModel_alreadyOfflineThenFurtherNonReadyStates_keepsOriginalLastSeen() {
        let original = Date(timeIntervalSince1970: 42)
        let viewModel = makeLive(connectionState: .offline(lastSeen: original))

        viewModel.apply(.accepted)
        viewModel.apply(.tlsHandshaking)

        #expect(viewModel.connectionState == .offline(lastSeen: original))
    }

    @Test @MainActor
    func mainWindowViewModel_batteryKnownWhileOnline_sidebarShowsConnectedWithPercent() {
        let viewModel = makeLive()

        viewModel.updateBatteryPercent(82)

        #expect(viewModel.connectionStateText == "Connected · 82%")
    }

    @Test @MainActor
    func mainWindowViewModel_batteryKnownWhileOffline_sidebarStillShowsOffline() {
        let viewModel = makeLive(connectionState: .offline(lastSeen: Self.fixedNow))

        viewModel.updateBatteryPercent(82)

        #expect(viewModel.connectionStateText.hasPrefix("Offline · seen "))
    }

    @Test @MainActor
    func mainWindowViewModel_peerUnpaired_showsNoPhoneYetAndDefaultName() {
        let viewModel = makeLive()

        viewModel.updatePeer(name: nil, lastSeen: nil)

        #expect(!viewModel.isPaired)
        #expect(viewModel.deviceName == MainWindowViewModel.notPairedDeviceName)
        #expect(viewModel.connectionStateText == "No phone yet.")
    }

    @Test @MainActor
    func mainWindowViewModel_peerPaired_adoptsNameAndLastSeenWhileOffline() {
        let viewModel = makeLive(connectionState: .offline(lastSeen: Self.fixedNow), isPaired: false)
        let lastSeen = Date(timeIntervalSince1970: 100)

        viewModel.updatePeer(name: "Pixel 9", lastSeen: lastSeen)

        #expect(viewModel.isPaired)
        #expect(viewModel.deviceName == "Pixel 9")
        #expect(viewModel.connectionState == .offline(lastSeen: lastSeen))
    }

    @Test @MainActor
    func mainWindowViewModel_stateStream_followsReadyThenDisconnected() async {
        let viewModel = makeLive(connectionState: .offline(lastSeen: Date(timeIntervalSince1970: 1)))
        let (stream, continuation) = AsyncStream<ConnectionStateMachine.ConnectionState>.makeStream()
        viewModel.observe(stream)

        continuation.yield(.ready)
        var attempts = 0
        while viewModel.isOffline, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(!viewModel.isOffline)

        continuation.yield(.disconnected(reason: "closed"))
        attempts = 0
        while !viewModel.isOffline, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(viewModel.connectionState == .offline(lastSeen: Self.fixedNow))
    }
}

/// Fake ``MainWindowSectionStore``: an in-memory `Int?`, no `UserDefaults` involved -- surviving
/// across two ``MainWindowViewModel`` instances the same way a real relaunch would survive across
/// two process launches.
private final class FakeMainWindowSectionStore: MainWindowSectionStore {
    var selectedSectionID: Int?
}
