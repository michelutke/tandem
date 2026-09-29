import Foundation

/// Composes the main window (E22-09), split out of `TandemApp.swift` purely to keep that file
/// under this repo's `file_length` lint budget, mirroring `SettingsComposition.swift`.
extension TandemMenuBarApp {
    /// No paired-session/status wiring exists yet for the device name, connection state, or
    /// per-section "turned off on the phone" state to react to (E22-02, E23) -- the same gap
    /// `MenuBarViewModel`'s own `stateStream: nil` documents -- so this is a fixed online stub
    /// until a future issue observes the real session/status stream. Cached once per process (like
    /// `settingsPairedDevicesViewModel`'s own scenario cache) so the persisted selection survives
    /// the window being closed and reopened via "Open Tandem" without re-reading `UserDefaults`
    /// mid-session.
    @MainActor
    static var mainWindowViewModel: MainWindowViewModel {
        if let existing = _mainWindowViewModel { return existing }
        let created = MainWindowViewModel(
            deviceName: "Tandem",
            connectionState: .online,
            sectionStore: UserDefaultsMainWindowSectionStore()
        )
        _mainWindowViewModel = created
        return created
    }

    nonisolated(unsafe) private static var _mainWindowViewModel: MainWindowViewModel?
}
