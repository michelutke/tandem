import FeatureFiles
import Observation
import SwiftUI
import TandemTransport

#if DEBUG
// FakeTandemSession (E12-12) is internal to TandemProtocol -- deliberately not exposed publicly,
// since its `send`/`receive` requirements would otherwise have to carry non-public generated
// protobuf types across the module boundary (see `FakeTandemSession`'s own doc comment). Reached
// here, under DEBUG only, exactly the way the E00-26 scenario seeding was always documented to.
@testable import TandemProtocol

/// Records that the Send File picker opened, then cancels it, so the scenario never shows a real panel.
@MainActor
@Observable
private final class ScenarioFilePicker: FilePicker {
    private(set) var opened = false

    func pickFiles() async -> [URL] {
        opened = true
        return []
    }
}

private struct ScenarioConnectedTransferService: FileTransferService {
    let isConnected = true

    func startOffer(for url: URL) async {}
}

/// The menu bar popover content rendered under a DEBUG `-UITestScenario` launch argument (E00-26),
/// split out of `TandemApp.swift` purely to keep that file under this repo's `file_length` lint
/// budget.
struct ScenarioView: View {
    /// The seeded peer name for the ``UITestScenario/pairedConnected`` scenario -- also asserted
    /// against by ``ScenarioPairedConnectedUITests``.
    static let pairedConnectedPeerName = "Pixel 8"

    let scenario: UITestScenario

    private var transferProgressViewModel: TransferProgressViewModel { Self.transferProgressViewModel }

    @State private var pairedConnectedViewModel = ScenarioView.makePairedConnectedViewModel()
    @State private var pairedConnectedDeviceStatusViewModel = ScenarioView.makePairedConnectedDeviceStatusViewModel()
    /// Backed by ``pairedConnectedSession`` (E23-07), the same shared fake session
    /// ``pairedConnectedViewModel`` and ``pairedConnectedDeviceStatusViewModel`` already observe,
    /// so a `Ring`/`RingStop` selected here shows up exactly like production wiring would.
    @State private var pairedConnectedFindPhoneViewModel: FindPhoneViewModel
    @State private var pairedConnectedPushClipboardViewModel = PushClipboardViewModel(sender: nil)
    @State private var pairedConnectedQuickActionsViewModel: QuickActionsViewModel
    @State private var pairedConnectedFilePicker: ScenarioFilePicker
    @State private var pairedConnectedSendEntryHandler: SendEntryHandler
    @State private var pairedDisconnectedViewModel = ScenarioView.makePairedDisconnectedViewModel()
    /// No session (E23-07) -- ``pairedDisconnectedQuickActionsViewModel``'s `isConnected: false`
    /// already disables this action, so there is nothing for it to send/observe.
    @State private var pairedDisconnectedFindPhoneViewModel = FindPhoneViewModel(session: nil)
    @State private var pairedDisconnectedPushClipboardViewModel = PushClipboardViewModel(sender: nil)
    @State private var pairedDisconnectedQuickActionsViewModel: QuickActionsViewModel
    @State private var failClosedErrorBannerViewModel = ScenarioView.makeFailClosedErrorBannerViewModel()
    @State private var versionMismatchMenuViewModels = ScenarioView.makeVersionMismatchMenuViewModels()

    init(scenario: UITestScenario) {
        self.scenario = scenario

        let pairedConnectedFindPhoneViewModel = FindPhoneViewModel(session: ScenarioView.pairedConnectedSession)
        let pairedConnectedPushClipboardViewModel = PushClipboardViewModel(sender: nil)
        _pairedConnectedFindPhoneViewModel = State(initialValue: pairedConnectedFindPhoneViewModel)
        _pairedConnectedPushClipboardViewModel = State(initialValue: pairedConnectedPushClipboardViewModel)
        let pairedConnectedFilePicker = ScenarioFilePicker()
        let pairedConnectedSendEntryHandler = SendEntryHandler(
            picker: pairedConnectedFilePicker,
            transfer: ScenarioConnectedTransferService()
        )
        _pairedConnectedFilePicker = State(initialValue: pairedConnectedFilePicker)
        _pairedConnectedSendEntryHandler = State(initialValue: pairedConnectedSendEntryHandler)
        _pairedConnectedQuickActionsViewModel = State(initialValue: ScenarioView.makeQuickActionsViewModel(
            isConnected: true,
            sendFile: { Task { _ = await pairedConnectedSendEntryHandler.sendFileQuickAction() } },
            findPhone: { pairedConnectedFindPhoneViewModel.select() },
            pushClipboard: { pairedConnectedPushClipboardViewModel.select() }
        ))

        let pairedDisconnectedFindPhoneViewModel = FindPhoneViewModel(session: nil)
        let pairedDisconnectedPushClipboardViewModel = PushClipboardViewModel(sender: nil)
        _pairedDisconnectedFindPhoneViewModel = State(initialValue: pairedDisconnectedFindPhoneViewModel)
        _pairedDisconnectedPushClipboardViewModel = State(initialValue: pairedDisconnectedPushClipboardViewModel)
        _pairedDisconnectedQuickActionsViewModel = State(initialValue: ScenarioView.makeQuickActionsViewModel(
            isConnected: false,
            sendFile: {},
            findPhone: { pairedDisconnectedFindPhoneViewModel.select() },
            pushClipboard: { pairedDisconnectedPushClipboardViewModel.select() }
        ))
    }

    var body: some View {
        switch scenario {
        case .notPaired:
            VStack(alignment: .leading, spacing: 8) {
                MenuBarContentView(
                    viewModel: MenuBarViewModel(stateStream: nil, peerName: nil),
                    deviceStatusViewModel: nil
                )
                SettingsMenuButton()
            }
        case .pairedConnected:
            VStack(alignment: .leading, spacing: 8) {
                MenuBarContentView(
                    viewModel: pairedConnectedViewModel,
                    deviceStatusViewModel: pairedConnectedDeviceStatusViewModel
                )
                QuickActionsView(
                    viewModel: pairedConnectedQuickActionsViewModel,
                    findPhoneViewModel: pairedConnectedFindPhoneViewModel,
                    pushClipboardViewModel: pairedConnectedPushClipboardViewModel
                )
                if pairedConnectedFilePicker.opened {
                    Text("File picker opened")
                        .accessibilityIdentifier("filePickerOpenedLabel")
                }
            }
            .acceptsFileDrops(pairedConnectedSendEntryHandler)
        case .pairedDisconnected:
            VStack(alignment: .leading, spacing: 8) {
                MenuBarContentView(viewModel: pairedDisconnectedViewModel, deviceStatusViewModel: nil)
                QuickActionsView(
                    viewModel: pairedDisconnectedQuickActionsViewModel,
                    findPhoneViewModel: pairedDisconnectedFindPhoneViewModel,
                    pushClipboardViewModel: pairedDisconnectedPushClipboardViewModel
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
        case .versionMismatchMenu:
            VStack(alignment: .leading, spacing: 8) {
                ErrorBannerView(viewModel: versionMismatchMenuViewModels.banner)
                MenuBarContentView(viewModel: versionMismatchMenuViewModels.menuBar, deviceStatusViewModel: nil)
            }
        case .localNetworkDenied:
            LocalNetworkPermissionBannerView(viewModel: ScenarioView.makeLocalNetworkPermissionViewModel())
        case .mainWindowOffline:
            MainWindowView(viewModel: ScenarioView.makeMainWindowOfflineViewModel())
        case .mainWindowFeatureDisabled:
            MainWindowView(viewModel: ScenarioView.makeMainWindowFeatureDisabledViewModel())
        case .photoGridPartialAccess:
            ScenarioView.makePhotoGridPartialAccessView()
        case .threadListSeeded:
            ScenarioView.makeThreadListSeededView()
        case .incomingCallActive:
            ScenarioView.makeIncomingCallActiveView()
        case .mirrorDeclined:
            ScenarioView.makeMirrorDeclinedView()

        case .transferProgressSeeded:
            TransferProgressRow(viewModel: transferProgressViewModel)
                .padding()
        }
    }

    private static let transferProgressViewModel: TransferProgressViewModel = {
        let viewModel = TransferProgressViewModel(
            id: "seeded", name: "report.pdf", totalBytes: 100, clock: ContinuousClock()
        ) {}
        viewModel.record(deliveredBytes: 42)
        return viewModel
    }()

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

    /// E15-16: both view models observe their own stream from one ``ConnectionStateRelay`` -- the
    /// same fan-out `MenuContentView` uses in production -- fed by a `FakeTandemSession` that fails
    /// with a version mismatch.
    private static func makeVersionMismatchMenuViewModels()
        -> (menuBar: MenuBarViewModel, banner: ErrorBannerViewModel) {
        let relay = ConnectionStateRelay()
        let session = FakeTandemSession()
        let viewModels = (
            menuBar: MenuBarViewModel(stateStream: relay.makeStream(), peerName: pairedConnectedPeerName),
            banner: ErrorBannerViewModel(stateStream: relay.makeStream(), peerName: pairedConnectedPeerName)
        )
        Task {
            await relay.attach(session)
            await session.emit(.failed(.versionMismatch))
        }
        return viewModels
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

    /// A no-op stub closure for the one action with no wiring yet -- this seeds view state for
    /// XCUITest, not a unit test, so recording call counts isn't needed here
    /// (``QuickActionsViewModelTests`` already covers that). `sendFile` (E40-10), `findPhone`
    /// (E23-07) and `pushClipboard` (E31-11) are real: they dispatch to their own scenario's
    /// handler/view model.
    private static func makeQuickActionsViewModel(
        isConnected: Bool,
        sendFile: @escaping () -> Void,
        findPhone: @escaping () -> Void,
        pushClipboard: @escaping () -> Void
    ) -> QuickActionsViewModel {
        QuickActionsViewModel(
            isConnected: isConnected,
            sendFile: sendFile,
            pushClipboard: pushClipboard,
            findPhone: findPhone,
            mirror: {}
        )
    }
}
#endif
