#if DEBUG
import SwiftUI
import TandemPairing
@testable import TandemProtocol

/// The popover, pairing and banner states of the `-UITestScenario` launch argument that need no
/// session of their own (design-conformance round: ringing, update needed, "unpaired this Mac",
/// "Paired.", the trust-error banner), split out of `ScenarioView.swift` to keep that file short.
struct ScenarioStateViews: View {
    let scenario: UITestScenario

    @State private var trustErrorBanner = ScenarioStateViews.makeTrustErrorBanner()

    var body: some View {
        switch scenario {
        case .popoverRinging:
            MenuBarContentView(
                viewModel: MenuBarViewModel(state: .connected(peerName: ScenarioView.pairedConnectedPeerName)),
                deviceStatusViewModel: nil,
                isRinging: true
            )
        case .popoverUpdateNeeded:
            MenuBarContentView(
                viewModel: MenuBarViewModel(state: .error),
                deviceStatusViewModel: nil,
                closeCode: .versionMismatch
            )
        case .popoverUnpairedNotice:
            MenuBarContentView(
                viewModel: MenuBarViewModel(state: .notPaired),
                deviceStatusViewModel: nil,
                unpairedNotice: "\(ScenarioView.pairedConnectedPeerName) unpaired this Mac."
            )
        case .pairingPaired:
            PairedView(stateText: "\(ScenarioView.pairedConnectedPeerName) is ready.", onDone: {})
        case .trustErrorBanner:
            ErrorBannerView(viewModel: trustErrorBanner)
        default:
            EmptyView()
        }
    }

    private static func makeTrustErrorBanner() -> ErrorBannerViewModel {
        let session = FakeTandemSession()
        let viewModel = ErrorBannerViewModel(
            stateStream: session.state, peerName: ScenarioView.pairedConnectedPeerName
        )
        Task { await session.emit(.failed(.pinMismatch)) }
        return viewModel
    }
}
#endif
