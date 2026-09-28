import SwiftUI
import TandemCrypto
import TandemTransport

#if DEBUG
// FakeTandemSession (E12-12) is internal to TandemProtocol -- deliberately not exposed publicly,
// since its `send`/`receive` requirements would otherwise have to carry non-public generated
// protobuf types across the module boundary (see `FakeTandemSession`'s own doc comment). Reached
// here, under DEBUG only, exactly the way the E00-26 scenario seeding was always documented to.
@testable import TandemProtocol
#endif

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
    #if DEBUG
    // E00-26: on headless CI runners the status item is unreliable to find/click, so a
    // `-UITestScenario` launch also opens a regular window with the same seeded content and
    // XCUITest asserts against that window instead. `SceneBuilder` has no support for a
    // conditional scene (an `if` alone crashes the compiler; `if`/`else` is a hard "closure
    // containing control flow statement" diagnostic on this toolchain), so the window is opened
    // imperatively from an `NSApplicationDelegateAdaptor` rather than declared in `body`.
    // DEBUG-only, gated the same as `UITestScenario` itself (invariant 2).
    @NSApplicationDelegateAdaptor(UITestScenarioWindowDelegate.self) private var scenarioWindowDelegate
    #endif

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
    nonisolated(unsafe) private static var retainedProductionLifecycle: AppComposition.RetainedLifecycle?

    /// Set instead of `retainedProductionLifecycle` if `startListener()` didn't start anything --
    /// surfaced by `MenuContentView` as a visible "Listener Unavailable" state (invariant 5),
    /// never retried silently.
    nonisolated(unsafe) fileprivate static var productionListenerFailureReason: AppComposition.StartFailure?

    var body: some Scene {
        MenuBarExtra("Tandem", systemImage: "circle.fill") {
            MenuContentView()
        }
        .menuBarExtraStyle(.window)
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

#if DEBUG
import AppKit

final class UITestScenarioWindowDelegate: NSObject, NSApplicationDelegate {
    private var scenarioWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // E15-22: one-shot trust seeding/clearing hooks exit the process immediately; the listener
        // hook (if requested) keeps it running as the ordinary menu bar app.
        HarnessHooks.runOneShotHooksIfRequested()
        HarnessHooks.startListenerIfRequested()

        guard UITestScenario.fromLaunchArguments() != nil else { return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: MenuContentView()))
        window.title = "Tandem UI Test Scenario"
        window.setContentSize(NSSize(width: 320, height: 200))
        window.makeKeyAndOrderFront(nil)
        scenarioWindow = window
    }
}
#endif

/// The menu bar popover content. Normally empty scaffolding until the connection UI (F-4.2)
/// lands; under a DEBUG `-UITestScenario` launch argument it renders the seeded scenario view
/// instead (identity bootstrap is never even evaluated in that case, so a seeded scenario never
/// depends on real Keychain access), so XCUITest has a deterministic, accessibility-identified
/// element to assert on. Otherwise, if identity bootstrap failed (E10-07b, D-75), that replaces
/// the ordinary "Tandem" content with a visible error.
struct MenuContentView: View {
    @State private var menuBarViewModel = MenuBarViewModel(stateStream: nil, peerName: nil)

    /// No paired-session wiring exists yet for ``findPhoneViewModel`` to send/observe `Ring`/
    /// `RingStop` on (E23-07's own `session: nil` below) -- until whichever issue first composes
    /// pairing together with Send File (E40-10), Push Clipboard (E31-11), and Mirror (E61-12) into
    /// ``AppComposition``, ``select()`` on this instance is a no-op.
    @State private var findPhoneViewModel = FindPhoneViewModel(session: nil)

    /// No paired-session wiring exists yet for the remaining three quick actions to react to
    /// (E22-02) -- the same gap `menuBarViewModel`'s own `stateStream: nil` above already has --
    /// so this is `isConnected: false` with no-op stub closures for those three, and
    /// ``findPhoneViewModel`` itself (also presently sessionless) for "Find Phone".
    @State private var quickActionsViewModel: QuickActionsViewModel

    init() {
        let findPhoneViewModel = FindPhoneViewModel(session: nil)
        _findPhoneViewModel = State(initialValue: findPhoneViewModel)
        _quickActionsViewModel = State(initialValue: QuickActionsViewModel(
            isConnected: false,
            sendFile: {},
            pushClipboard: {},
            findPhone: { findPhoneViewModel.select() },
            mirror: {}
        ))
    }

    /// Same wiring gap as ``menuBarViewModel``/``quickActionsViewModel`` above: no paired-session
    /// stream exists yet (E22-02), so this never observes a real fail-closed event until a future
    /// issue composes real session wiring into ``AppComposition``.
    @State private var errorBannerViewModel = ErrorBannerViewModel(stateStream: nil, peerName: nil)

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
                MenuBarContentView(viewModel: menuBarViewModel, deviceStatusViewModel: nil)
                QuickActionsView(viewModel: quickActionsViewModel, findPhoneViewModel: findPhoneViewModel)
            }
        }
    }
}

#if DEBUG
private struct ScenarioView: View {
    /// The seeded peer name for the ``UITestScenario/pairedConnected`` scenario -- also asserted
    /// against by ``ScenarioPairedConnectedUITests``.
    static let pairedConnectedPeerName = "Pixel 8"

    let scenario: UITestScenario

    @State private var pairedConnectedViewModel = ScenarioView.makePairedConnectedViewModel()
    @State private var pairedConnectedDeviceStatusViewModel = ScenarioView.makePairedConnectedDeviceStatusViewModel()
    /// Backed by ``pairedConnectedSession`` (E23-07), the same shared fake session
    /// ``pairedConnectedViewModel`` and ``pairedConnectedDeviceStatusViewModel`` already observe,
    /// so a `Ring`/`RingStop` selected here shows up exactly like production wiring would.
    @State private var pairedConnectedFindPhoneViewModel: FindPhoneViewModel
    @State private var pairedConnectedQuickActionsViewModel: QuickActionsViewModel
    @State private var pairedDisconnectedViewModel = ScenarioView.makePairedDisconnectedViewModel()
    /// No session (E23-07) -- ``pairedDisconnectedQuickActionsViewModel``'s `isConnected: false`
    /// already disables this action, so there is nothing for it to send/observe.
    @State private var pairedDisconnectedFindPhoneViewModel = FindPhoneViewModel(session: nil)
    @State private var pairedDisconnectedQuickActionsViewModel: QuickActionsViewModel
    @State private var failClosedErrorBannerViewModel = ScenarioView.makeFailClosedErrorBannerViewModel()

    init(scenario: UITestScenario) {
        self.scenario = scenario

        let pairedConnectedFindPhoneViewModel = FindPhoneViewModel(session: ScenarioView.pairedConnectedSession)
        _pairedConnectedFindPhoneViewModel = State(initialValue: pairedConnectedFindPhoneViewModel)
        _pairedConnectedQuickActionsViewModel = State(initialValue: ScenarioView.makeQuickActionsViewModel(
            isConnected: true,
            findPhone: { pairedConnectedFindPhoneViewModel.select() }
        ))

        let pairedDisconnectedFindPhoneViewModel = FindPhoneViewModel(session: nil)
        _pairedDisconnectedFindPhoneViewModel = State(initialValue: pairedDisconnectedFindPhoneViewModel)
        _pairedDisconnectedQuickActionsViewModel = State(initialValue: ScenarioView.makeQuickActionsViewModel(
            isConnected: false,
            findPhone: { pairedDisconnectedFindPhoneViewModel.select() }
        ))
    }

    var body: some View {
        switch scenario {
        case .notPaired:
            MenuBarContentView(viewModel: MenuBarViewModel(stateStream: nil, peerName: nil), deviceStatusViewModel: nil)
        case .pairedConnected:
            VStack(alignment: .leading, spacing: 8) {
                MenuBarContentView(
                    viewModel: pairedConnectedViewModel,
                    deviceStatusViewModel: pairedConnectedDeviceStatusViewModel
                )
                QuickActionsView(
                    viewModel: pairedConnectedQuickActionsViewModel,
                    findPhoneViewModel: pairedConnectedFindPhoneViewModel
                )
            }
        case .pairedDisconnected:
            VStack(alignment: .leading, spacing: 8) {
                MenuBarContentView(viewModel: pairedDisconnectedViewModel, deviceStatusViewModel: nil)
                QuickActionsView(
                    viewModel: pairedDisconnectedQuickActionsViewModel,
                    findPhoneViewModel: pairedDisconnectedFindPhoneViewModel
                )
            }
        case .failClosedError:
            let presenter = ErrorPresenter(reasonName: "versionMismatch")
            VStack(alignment: .leading, spacing: 8) {
                Text(presenter.localizedTitle)
                    .accessibilityIdentifier("failClosedErrorLabel")
                    .accessibilityLabel(presenter.localizedTitle)
                ErrorBannerView(viewModel: failClosedErrorBannerViewModel)
            }
        case .localNetworkDenied:
            LocalNetworkPermissionBannerView(viewModel: ScenarioView.makeLocalNetworkPermissionViewModel())
        }
    }

    /// The one ``FakeTandemSession`` (E12-12) shared by ``makePairedConnectedViewModel()`` and
    /// ``makePairedConnectedDeviceStatusViewModel()`` for this scenario window's lifetime -- both
    /// view models observe the same session, exactly as production wiring would.
    private static let pairedConnectedSession = FakeTandemSession()

    /// Seeds ``pairedConnectedSession`` already `Ready`, so the scenario window renders "Connected
    /// to Pixel 8" and the battery placeholder (until a `DeviceStatus` arrives, below) without any
    /// real network/Keychain access.
    private static func makePairedConnectedViewModel() -> MenuBarViewModel {
        let viewModel = MenuBarViewModel(stateStream: pairedConnectedSession.state, peerName: pairedConnectedPeerName)
        Task { await pairedConnectedSession.emit(.ready) }
        return viewModel
    }

    /// Seeds a `DeviceStatus` on ``pairedConnectedSession`` only when
    /// ``UITestScenario/deviceStatusSeedRequested(_:)`` -- the plain `pairedConnected` scenario
    /// (no flag) never sees a `DeviceStatus`, so its own battery placeholder assertion
    /// (`ScenarioPairedConnectedUITests`) stays deterministic.
    private static func makePairedConnectedDeviceStatusViewModel() -> DeviceStatusViewModel {
        let viewModel = DeviceStatusViewModel(session: pairedConnectedSession)
        if UITestScenario.deviceStatusSeedRequested() {
            var status = Tandem_V1_DeviceStatus()
            status.batteryLevel = 82
            status.isCharging = true
            status.networkType = .wifi
            Task {
                let frame = InboundFrame(channel: .status, seq: 1, ack: 0, payload: .deviceStatus(status))
                await pairedConnectedSession.inject(frame)
            }
        }
        return viewModel
    }

    /// Seeds a ``FakeTandemSession`` (E12-12) transitioned to `.disconnected` instead of `.ready`,
    /// so the scenario window renders "Disconnected" for the ``UITestScenario/pairedDisconnected``
    /// case (E22-02) -- a previously-paired peer whose session isn't currently `Ready`.
    private static func makePairedDisconnectedViewModel() -> MenuBarViewModel {
        let session = FakeTandemSession()
        let viewModel = MenuBarViewModel(stateStream: session.state, peerName: pairedConnectedPeerName)
        Task { await session.emit(.disconnected(reason: "peer disconnected")) }
        return viewModel
    }

    /// Seeds a fresh ``FakeTandemSession`` (E12-12) that emits `.failed(.versionMismatch)`, so the
    /// scenario window's ``ErrorBannerView`` renders the exact E22-07 version-mismatch banner text
    /// alongside the existing E12-10 status-line text above -- both driven by the same close code,
    /// on separate view models, matching how they'll compose once real session wiring lands.
    private static func makeFailClosedErrorBannerViewModel() -> ErrorBannerViewModel {
        let session = FakeTandemSession()
        let viewModel = ErrorBannerViewModel(stateStream: session.state, peerName: pairedConnectedPeerName)
        Task { await session.emit(.failed(.versionMismatch)) }
        return viewModel
    }

    /// Seeds a `BonjourPublishError.policyDenied` error before the view model even starts
    /// observing -- `AsyncStream.makeStream()`'s default `.unbounded` buffering policy means the
    /// yield is still delivered once ``LocalNetworkPermissionViewModel.init(errors:urlOpener:)``'s
    /// own observation `Task` gets scheduled, so this scenario's banner appears without any real
    /// `BonjourPublisher`/advertise wiring (E21-03: none exists in this scenario window). The real
    /// `WorkspaceURLOpener` is used here, not a fake -- unlike `LocalNetworkPermissionViewModelTests`,
    /// this is a real interactive window a developer can click through, and the XCUITest itself
    /// only asserts the button exists, never taps it.
    private static func makeLocalNetworkPermissionViewModel() -> LocalNetworkPermissionViewModel {
        let (stream, continuation) = AsyncStream<BonjourPublishError>.makeStream()
        continuation.yield(.policyDenied)
        return LocalNetworkPermissionViewModel(errors: stream, urlOpener: WorkspaceURLOpener())
    }

    /// No-op stub closures for the two actions with no wiring yet -- this seeds view state for
    /// XCUITest, not a unit test, so recording call counts isn't needed here
    /// (``QuickActionsViewModelTests`` already covers that). `findPhone` (E23-07) is real: it
    /// dispatches to its own scenario's ``FindPhoneViewModel``.
    private static func makeQuickActionsViewModel(
        isConnected: Bool,
        findPhone: @escaping () -> Void
    ) -> QuickActionsViewModel {
        QuickActionsViewModel(
            isConnected: isConnected,
            sendFile: {},
            pushClipboard: {},
            findPhone: findPhone,
            mirror: {}
        )
    }
}
#endif
