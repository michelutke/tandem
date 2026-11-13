import SwiftUI
import TandemStore

/// The menu bar item's icon: the SF Symbol of ``MenuBarViewModel/systemImageName`` for the current
/// connection state. Owns its own ``MenuBarViewModel`` over the running listener's state stream
/// (the popover keeps its own, built the same way) and follows the paired peer.
struct MenuBarStatusIcon: View {
    @State private var viewModel: MenuBarViewModel
    private let pairedPeer: PairedPeerState?

    init() {
        let lifecycle = TandemMenuBarApp.retainedProductionLifecycle
        pairedPeer = lifecycle?.pairedPeer
        _viewModel = State(initialValue: MenuBarViewModel(
            stateStream: lifecycle?.makeMenuBarStateStream?(),
            peerName: lifecycle?.pairedPeer.displayName
        ))
    }

    var body: some View {
        Image(systemName: viewModel.systemImageName)
            .accessibilityLabel(viewModel.label)
            .onChange(of: pairedPeer?.displayName) { viewModel.updatePeerName(pairedPeer?.displayName) }
    }
}
