import TandemDevices

/// Composes the Settings window's Paired Devices tab (E22-05), split out of `TandemApp.swift`
/// purely to keep that file under this repo's `file_length` lint budget.
extension TandemMenuBarApp {
    /// The real E14-26 composition against ``retainedProductionLifecycle`` for an ordinary
    /// launch; under a DEBUG `-UITestScenario` launch, production wiring never started at all
    /// (`init()`'s own guard), so this is a seeded fake instead (``SettingsScenarioSupport``) --
    /// the same reasoning `ScenarioView` already applies to every other scenario dependency in
    /// this target.
    @MainActor
    static var settingsPairedDevicesViewModel: PairedDevicesViewModel? {
        #if DEBUG
        if UITestScenario.fromLaunchArguments() != nil {
            return scenarioPairedDevicesViewModel
        }
        #endif
        guard let lifecycle = retainedProductionLifecycle else { return nil }
        return AppComposition.makePairedDevicesViewModel(lifecycle: lifecycle)
    }

    #if DEBUG
    /// Built once per process on first Settings-window open under `-UITestScenario` -- a fresh
    /// `PairedDevicesViewModel` per open would still show the same seeded row (its own
    /// `TrustStore` is a real on-disk file), but caching here matches how
    /// `retainedProductionLifecycle` itself is only ever set up once.
    @MainActor
    private static var scenarioPairedDevicesViewModel: PairedDevicesViewModel {
        if let existing = _scenarioPairedDevicesViewModel { return existing }
        let created = SettingsScenarioSupport.makePairedDevicesViewModel()
        _scenarioPairedDevicesViewModel = created
        return created
    }

    nonisolated(unsafe) private static var _scenarioPairedDevicesViewModel: PairedDevicesViewModel?
    #endif
}
