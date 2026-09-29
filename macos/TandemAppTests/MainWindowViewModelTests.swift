import Foundation
import Testing

@testable import TandemApp

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
}

/// Fake ``MainWindowSectionStore``: an in-memory `Int?`, no `UserDefaults` involved -- surviving
/// across two ``MainWindowViewModel`` instances the same way a real relaunch would survive across
/// two process launches.
private final class FakeMainWindowSectionStore: MainWindowSectionStore {
    var selectedSectionID: Int?
}
