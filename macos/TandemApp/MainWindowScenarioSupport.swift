#if DEBUG
import Foundation

/// `ScenarioView`'s own `.mainWindowOffline`/`.mainWindowFeatureDisabled` factories (E22-09), split
/// out of `TandemApp.swift` purely to keep that file under this repo's `file_length` lint budget.
extension ScenarioView {
    /// Fixed local time (14:02) so ``MainWindowUITests``'s "Offline · seen 14:02" assertion is
    /// deterministic regardless of the host's real clock -- both this seed and
    /// ``MainWindowViewModel/formattedTime(_:)`` format against `Calendar.current`/`.current` time
    /// zone, so the printed digits match on any machine.
    static func makeMainWindowOfflineViewModel() -> MainWindowViewModel {
        let lastSeen = Calendar.current.date(
            from: DateComponents(year: 2026, month: 1, day: 1, hour: 14, minute: 2)
        ) ?? Date()
        return MainWindowViewModel(
            deviceName: pairedConnectedPeerName,
            connectionState: .offline(lastSeen: lastSeen),
            sectionStore: InMemoryMainWindowSectionStore()
        )
    }

    /// Messages (the default selected section) turned off on the phone -- the content area shows
    /// the shared "Turned off on the phone." empty state without any further interaction.
    static func makeMainWindowFeatureDisabledViewModel() -> MainWindowViewModel {
        MainWindowViewModel(
            deviceName: pairedConnectedPeerName,
            connectionState: .online,
            disabledSectionIDs: [MainWindowViewModel.sections[0].id],
            sectionStore: InMemoryMainWindowSectionStore()
        )
    }
}

/// In-memory ``MainWindowSectionStore`` fake for scenario windows -- unlike
/// ``UserDefaultsMainWindowSectionStore``, never touches real `UserDefaults` state.
private final class InMemoryMainWindowSectionStore: MainWindowSectionStore {
    var selectedSectionID: Int?
}
#endif
