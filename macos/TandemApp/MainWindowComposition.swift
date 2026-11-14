import FeatureFiles
import FeatureMirror
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
                stateStream: lifecycle.makeBannerStateStream?(),
                peerName: lifecycle.pairedPeer.displayName,
                pairedPeer: lifecycle.pairedPeer
            )
        )
        _mainWindowServices = created
        return created
    }

    /// Drops the cached main-window view model and services so the next read rebuilds them from
    /// the lifecycle of a start that succeeded after an earlier failure.
    @MainActor
    static func resetMainWindowCaches() {
        _mainWindowViewModel = nil
        _mainWindowServices = nil
    }

    /// Opens the pairing window from the main window's "Pair phone" actions.
    @MainActor
    static func openPairingWindow() {
        guard let lifecycle = retainedProductionLifecycle else { return }
        SharedPairingPresenter.presenter(for: lifecycle.pairing).openPairingWindow()
    }

    nonisolated(unsafe) private static var _mainWindowViewModel: MainWindowViewModel?
    nonisolated(unsafe) private static var _mainWindowServices: MainWindowServices?
}

/// The one pairing presenter shared by the menu bar and the main window. Lives outside
/// TandemApp.swift because the release-scan fixture build replaces that file wholesale.
@MainActor
enum SharedPairingPresenter {
    private static var retained: MacPairingPresenter?

    static func presenter(for composition: MacPairingComposition) -> MacPairingPresenter {
        if let retained { return retained }
        let presenter = MacPairingPresenter(composition: composition)
        retained = presenter
        return presenter
    }
}

/// The Find Phone and Mirror models every `MenuContentView` value shares. SwiftUI builds that view
/// many times; models made per `init` left the session wiring pointing at an instance no view shows.
@MainActor
enum SharedSessionModels {
    struct Models {
        let findPhone: FindPhoneViewModel
        let mirror: MirrorRequestViewModel
    }

    private static var retained: (owner: ObjectIdentifier, models: Models)?

    static func models(for lifecycle: AppComposition.RetainedLifecycle?) -> Models {
        guard let lifecycle else {
            return Models(findPhone: FindPhoneViewModel(session: nil), mirror: MirrorRequestViewModel(session: nil))
        }
        let owner = ObjectIdentifier(lifecycle.mirror)
        if let retained, retained.owner == owner { return retained.models }
        let live = lifecycle.sessionFeatures.live
        let findPhone = FindPhoneViewModel(session: live.session)
        live.onSessionChanged = { findPhone.sessionChanged($0) }
        let mirror = MirrorRequestViewModel(session: nil, peerName: lifecycle.pairedPeer.displayName)
        lifecycle.mirror.bind(mirror)
        let models = Models(findPhone: findPhone, mirror: mirror)
        retained = (owner, models)
        return models
    }
}
