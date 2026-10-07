import FeatureFiles
import Foundation

/// Composes the main window (E22-09), split out of `TandemApp.swift` purely to keep that file
/// under this repo's `file_length` lint budget, mirroring `SettingsComposition.swift`.
extension TandemMenuBarApp {
    /// The paired peer's name and last-seen time, followed by the real connection-state stream
    /// (``MainWindowViewModel/observe(_:)``). Cached once per process (like
    /// `settingsPairedDevicesViewModel`'s own scenario cache) so the persisted selection survives
    /// the window being closed and reopened via "Open Tandem" without re-reading `UserDefaults`
    /// mid-session.
    @MainActor
    static var mainWindowViewModel: MainWindowViewModel {
        if let existing = _mainWindowViewModel { return existing }
        let lifecycle = retainedProductionLifecycle
        let record = lifecycle?.pairedPeer.record
        let created = MainWindowViewModel(
            deviceName: record?.displayName ?? MainWindowViewModel.notPairedDeviceName,
            connectionState: .offline(lastSeen: record?.lastSeen ?? Date()),
            isPaired: record != nil,
            sectionStore: UserDefaultsMainWindowSectionStore()
        )
        created.observe(lifecycle?.makeMenuBarStateStream?())
        _mainWindowViewModel = created
        return created
    }

    /// The live section data for an ordinary launch; `nil` when no listener started.
    @MainActor
    static var mainWindowServices: MainWindowServices? {
        if let existing = _mainWindowServices { return existing }
        guard let lifecycle = retainedProductionLifecycle else { return nil }
        let features = lifecycle.sessionFeatures
        let created = MainWindowServices(
            live: features.live,
            messaging: features.messaging,
            photos: features.photos,
            transferProgress: features.transferProgress,
            sendEntryHandler: SendEntryHandler(picker: OpenPanelFilePicker(), transfer: features.fileTransfer),
            activeCall: features.activeCall,
            pairedPeer: lifecycle.pairedPeer,
            pairedDevices: settingsPairedDevicesViewModel,
            rotation: settingsRotationViewModel,
            errorBanner: ErrorBannerViewModel(
                stateStream: lifecycle.makeMenuBarStateStream?(),
                peerName: lifecycle.pairedPeer.displayName
            )
        )
        _mainWindowServices = created
        return created
    }

    /// Opens the pairing window from the main window's "Pair phone" actions.
    @MainActor
    static func openPairingWindow() {
        guard let lifecycle = retainedProductionLifecycle else { return }
        MenuContentView.pairingPresenter(for: lifecycle.pairing).openPairingWindow()
    }

    nonisolated(unsafe) private static var _mainWindowViewModel: MainWindowViewModel?
    nonisolated(unsafe) private static var _mainWindowServices: MainWindowServices?
}
