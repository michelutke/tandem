import FeatureFiles
import FeatureMirror
import SwiftUI
import TandemCrypto
import TandemDevices
import TandemStore
import TandemTransport

/// Maps a failure reason to a user-visible, secret-free error string (E12-10, invariant 5).
/// Pure value type; no dependencies on the app state or UI framework.
struct ErrorPresenter: Sendable {
    /// The failure reason, as the name of a CloseCode case (e.g., "versionMismatch", "protocolTimeout").
    let reasonName: String

    /// Title shown in the menu's connection-status area.
    var title: String {
        switch reasonName {
        case "versionMismatch":
            return "error.versionMismatch"
        case "protocolTimeout":
            return "error.timeout"
        case "limitExceeded":
            return "error.unknownPeer"
        case "malformedFrame":
            return "error.malformedFrame"
        case "creditViolation":
            return "error.creditViolation"
        case "pinMismatch":
            return "error.pinMismatch"
        default:
            return "error.unknown"
        }
    }

    /// Localized English text for the title (test-only; production uses Localizable.strings).
    var localizedTitle: String {
        switch reasonName {
        case "versionMismatch":
            return "Version mismatch."
        case "protocolTimeout":
            return "Timeout."
        case "limitExceeded":
            return "Too many connections."
        case "malformedFrame":
            return "Corrupted data received."
        case "creditViolation":
            return "Data flow error."
        case "pinMismatch":
            return "Untrusted device refused."
        default:
            return "Error."
        }
    }

    /// Detail string (secondary text). Empty for now; may be filled in a future issue.
    var detail: String {
        ""
    }
}

@main
struct TandemMenuBarApp: App {
    @NSApplicationDelegateAdaptor(TandemAppDelegate.self) private var appDelegate

    /// Starts the production listener (E22-01's own follow-up: "production listener startup") for
    /// every ordinary launch -- Debug or Release. Skipped only when a DEBUG harness or
    /// `-UITestScenario` launch argument is present, matching exactly the set `HarnessHooks`
    /// itself checks, so this never races the harness's own listener and a seeded scenario never
    /// touches the real network/Keychain.
    init() {
        guard Self.retainedProductionLifecycle == nil, Self.productionListenerFailureReason == nil else { return }
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "HarnessListenerPort") == nil,
              UserDefaults.standard.string(forKey: "HarnessSeedTrust") == nil,
              !UserDefaults.standard.bool(forKey: "HarnessClearTrust"),
              UITestScenario.fromLaunchArguments() == nil else { return }
        #endif
        switch AppComposition.startListener() {
        case .success(let lifecycle):
            Self.retainedProductionLifecycle = lifecycle
        case .failure(let reason):
            Self.productionListenerFailureReason = reason
        }
    }

    /// Keeps ``AppComposition/startListener()``'s lifecycle controllers alive for the process
    /// lifetime, once started -- `init()` only ever calls `startListener()` once per process (the
    /// guard above), so a second `App.init()` can't leak a second listener.
    nonisolated(unsafe) static private(set) var retainedProductionLifecycle: AppComposition.RetainedLifecycle?

    /// Set instead of `retainedProductionLifecycle` if `startListener()` didn't start anything --
    /// surfaced by `MenuContentView` as a visible "Listener Unavailable" state (invariant 5),
    /// never retried silently.
    nonisolated(unsafe) fileprivate static var productionListenerFailureReason: AppComposition.StartFailure?

    var body: some Scene {
        MenuBarExtra("Tandem", systemImage: "circle.fill") {
            MenuContentView()
        }
        .menuBarExtraStyle(.window)

        Window("Tandem", id: "main") {
            MainWindowView(
                viewModel: Self.mainWindowViewModel,
                photoService: Self.retainedProductionLifecycle?.sessionFeatures.photos
            )
        }

        Settings {
            SettingsView(
                pairedDevicesViewModel: Self.settingsPairedDevicesViewModel,
                rotationViewModel: Self.settingsRotationViewModel
            )
        }
    }
}

/// Ensures the Mac's mTLS identity (key + self-signed certificate + `SecIdentity`, E10-07) exists,
/// over the `KeychainStoreFactory`-selected store, the first time `MenuContentView` is rendered --
/// Swift globals are lazily and thread-safely initialized on first access. No silent fallback
/// (D-75, invariant 5): a failure here (e.g. `-34018` on an unsigned dev build with no
/// `keychain-access-groups` entitlement) is recorded and surfaced as a visible
/// "Identity Unavailable" state instead of the ordinary menu content.
private let identityBootstrapFailureReason: String? = {
    do {
        _ = try SecIdentityProvider(keychainStore: KeychainStoreFactory.make()).getOrCreateSecIdentity()
        return nil
    } catch {
        return String(describing: error)
    }
}()

/// Shows the main window on launch/Dock reopen (the app has a Dock icon, ui-spec), the pairing
/// window on launch when unpaired, and in DEBUG hosts the E00-26 scenario window.
///
/// E00-26: on headless CI runners the status item is unreliable to find/click, so a
/// `-UITestScenario` launch also opens a regular window with the same seeded content and
/// XCUITest asserts against that window instead. `SceneBuilder` has no support for a
/// conditional scene (an `if` alone crashes the compiler; `if`/`else` is a hard "closure
/// containing control flow statement" diagnostic on this toolchain), so the window is opened
/// imperatively from this delegate rather than declared in `body`. DEBUG-only, gated the same as
/// `UITestScenario` itself (invariant 2).
@MainActor
final class TandemAppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    private var scenarioWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // E15-22: one-shot trust seeding/clearing hooks exit the process immediately; the listener
        // hook (if requested) keeps it running as the ordinary menu bar app.
        HarnessHooks.runOneShotHooksIfRequested()
        HarnessHooks.startListenerIfRequested()

        if let scenario = UITestScenario.fromLaunchArguments() {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MenuContentView()))
            window.title = "Tandem UI Test Scenario"
            let conversationSize = NSSize(width: 640, height: 480)
            window.setContentSize(scenario == .conversationSeeded ? conversationSize : NSSize(width: 320, height: 200))
            window.makeKeyAndOrderFront(nil)
            scenarioWindow = window
            return
        }
        #endif
        guard let lifecycle = TandemMenuBarApp.retainedProductionLifecycle else { return }
        showMainWindow()
        if lifecycle.pairedPeer.displayName == nil {
            let presenter = MenuContentView.pairingPresenter(for: lifecycle.pairing)
            Task {
                try? await ContinuousClock().sleep(for: .seconds(1))
                presenter.openPairingWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow() ? false : true
    }

    /// Brings the SwiftUI `Window("Tandem", id: "main")` forward; `false` if it doesn't exist yet,
    /// so the system's default reopen handling creates it.
    @discardableResult
    private func showMainWindow() -> Bool {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) else {
            return false
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

/// The menu bar popover content. Normally empty scaffolding until the connection UI (F-4.2)
/// lands; under a DEBUG `-UITestScenario` launch argument it renders the seeded scenario view
/// instead (identity bootstrap is never even evaluated in that case, so a seeded scenario never
/// depends on real Keychain access), so XCUITest has a deterministic, accessibility-identified
/// element to assert on. Otherwise, if identity bootstrap failed (E10-07b, D-75), that replaces
/// the ordinary "Tandem" content with a visible error.
struct MenuContentView: View {
    /// E22-11: real ``ConnectionStateMachine/ConnectionState`` stream + display name, wired from
    /// ``AppComposition/startListener()``'s `RetainedLifecycle`.
    @State private var menuBarViewModel: MenuBarViewModel

    /// No paired-session/``ClipboardSender`` wiring exists yet for ``findPhoneViewModel``/
    /// ``pushClipboardViewModel`` (E23-07/E31-11's own `nil` below) -- until whichever issue first
    /// composes pairing together with Send File (E40-10) and Mirror (E61-12) into
    /// ``AppComposition``, ``select()`` on either instance is a no-op.
    @State private var findPhoneViewModel = FindPhoneViewModel(session: nil)
    @State private var pushClipboardViewModel = PushClipboardViewModel(sender: nil)
    @State private var mirrorRequestViewModel = MirrorRequestViewModel(session: nil)

    /// The remaining two quick actions (E22-02) share `menuBarViewModel`'s own sessionless gap
    /// above, so this is `isConnected: false` with no-op stub closures for those two.
    @State private var quickActionsViewModel: QuickActionsViewModel

    /// No transfer service is composed yet (same gap as above), so drops and the Send File picker
    /// yield `notConnected` until a later issue passes one in.
    @State private var sendEntryHandler = SendEntryHandler(picker: OpenPanelFilePicker(), transfer: nil)
    private let transferProgress: TransferProgressCenter?
    private let activeCall: ActiveCallAlert?
    private let activeNowPlaying: ActiveNowPlaying?

    /// Same real wiring as ``menuBarViewModel`` above (E22-11); pre-pin-check rejections (E22-10,
    /// D-59/D-76) never reach here.
    @State private var errorBannerViewModel: ErrorBannerViewModel

    private let pairingPresenter: MacPairingPresenter?
    private let pairedPeer: PairedPeerState?

    private static var retainedPairingPresenter: MacPairingPresenter?

    static func pairingPresenter(for composition: MacPairingComposition) -> MacPairingPresenter {
        if let retainedPairingPresenter { return retainedPairingPresenter }
        let presenter = MacPairingPresenter(composition: composition)
        retainedPairingPresenter = presenter
        return presenter
    }

    init() {
        let lifecycle = TandemMenuBarApp.retainedProductionLifecycle
        pairingPresenter = lifecycle.map { Self.pairingPresenter(for: $0.pairing) }
        transferProgress = lifecycle?.sessionFeatures.transferProgress
        activeCall = lifecycle?.sessionFeatures.activeCall
        activeNowPlaying = lifecycle?.sessionFeatures.activeNowPlaying
        pairedPeer = lifecycle?.pairedPeer
        let peerName = lifecycle?.pairedPeer.displayName
        _menuBarViewModel = State(initialValue: MenuBarViewModel(
            stateStream: lifecycle?.makeMenuBarStateStream?(),
            peerName: peerName
        ))
        _errorBannerViewModel = State(initialValue: ErrorBannerViewModel(
            stateStream: lifecycle?.makeMenuBarStateStream?(),
            peerName: peerName
        ))
        let findPhoneViewModel = FindPhoneViewModel(session: nil)
        _findPhoneViewModel = State(initialValue: findPhoneViewModel)
        let mirrorRequestViewModel = MirrorRequestViewModel(session: nil)
        _mirrorRequestViewModel = State(initialValue: mirrorRequestViewModel)
        lifecycle?.mirror.bind(mirrorRequestViewModel)
        let pushClipboardViewModel = PushClipboardViewModel(sender: nil)
        _pushClipboardViewModel = State(initialValue: pushClipboardViewModel)
        let sendEntryHandler = SendEntryHandler(
            picker: OpenPanelFilePicker(),
            transfer: lifecycle?.sessionFeatures.fileTransfer
        )
        _sendEntryHandler = State(initialValue: sendEntryHandler)
        NSApplication.shared.servicesProvider = Self.finderServicesProvider(handler: sendEntryHandler)
        let quickActionsViewModel = QuickActionsViewModel(
            isConnected: false,
            sendFile: { Task { _ = await sendEntryHandler.sendFileQuickAction() } },
            pushClipboard: { pushClipboardViewModel.select() },
            findPhone: { findPhoneViewModel.select() },
            mirror: { mirrorRequestViewModel.request() }
        )
        quickActionsViewModel.observeConnection(lifecycle?.makeMenuBarStateStream?())
        _quickActionsViewModel = State(initialValue: quickActionsViewModel)
    }

    private func syncPairedPeer() {
        pairedPeer?.refresh()
        menuBarViewModel.updatePeerName(pairedPeer?.displayName)
    }

    private static var retainedFinderServicesProvider: FinderServicesProvider?

    private static func finderServicesProvider(handler: SendEntryHandler) -> FinderServicesProvider {
        let provider = FinderServicesProvider(handler: handler)
        retainedFinderServicesProvider = provider
        return provider
    }

    var body: some View {
        #if DEBUG
        if let scenario = UITestScenario.fromLaunchArguments() {
            ScenarioView(scenario: scenario)
        } else {
            defaultContent
        }
        #else
        defaultContent
        #endif
    }

    @ViewBuilder
    private var defaultContent: some View {
        if let reason = identityBootstrapFailureReason {
            Text("Identity Unavailable")
                .accessibilityIdentifier("identityUnavailableLabel")
                .accessibilityLabel("Identity Unavailable: \(reason)")
        } else if TandemMenuBarApp.productionListenerFailureReason != nil {
            Text("Listener Unavailable")
                .accessibilityIdentifier("listenerUnavailableLabel")
                .accessibilityLabel("Listener Unavailable")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ErrorBannerView(viewModel: errorBannerViewModel)
                MenuBarContentView(
                    viewModel: menuBarViewModel,
                    deviceStatusViewModel: nil,
                    onPairPhone: { pairingPresenter?.openPairingWindow() }
                )
                if let transferProgress {
                    TransferProgressListView(center: transferProgress)
                }
                QuickActionsView(
                    viewModel: quickActionsViewModel,
                    findPhoneViewModel: findPhoneViewModel,
                    pushClipboardViewModel: pushClipboardViewModel,
                    mirrorRequestViewModel: mirrorRequestViewModel
                )
                if let activeCall {
                    ActiveCallHangUpView(activeCall: activeCall)
                }
                if let activeNowPlaying {
                    ActiveNowPlayingView(activeNowPlaying: activeNowPlaying)
                }
                OpenTandemMenuButton()
                SettingsMenuButton()
            }
            .acceptsFileDrops(sendEntryHandler)
            .onAppear { syncPairedPeer() }
            .onChange(of: pairedPeer?.displayName) { syncPairedPeer() }
        }
    }
}
