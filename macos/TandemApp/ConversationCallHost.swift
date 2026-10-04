import FeatureCalls
import FeatureMessaging
import SwiftUI
import TandemTransport

/// Hosts ``PlaceCallView`` in the conversation header (E52-10) so FeatureMessaging never depends on
/// FeatureCalls. Dials over the same session the conversation sends SMS on.
enum ConversationCallHost {
    @MainActor
    static func headerAccessory(
        session: any TandemSession,
        syncSource: any ConversationSyncSource
    ) -> @MainActor (String) -> AnyView {
        { number in
            AnyView(ConversationCallButton(session: session, syncSource: syncSource, number: number))
        }
    }
}

private struct ConversationCallButton: View {
    @State private var viewModel: PlaceCallViewModel
    private let number: String

    init(session: any TandemSession, syncSource: any ConversationSyncSource, number: String) {
        _viewModel = State(initialValue: PlaceCallViewModel(
            session: session,
            simSource: ConversationSimSource(syncSource: syncSource)
        ))
        self.number = number
    }

    var body: some View {
        PlaceCallView(viewModel: viewModel, number: number)
    }
}

private struct ConversationSimSource: PlaceCallSimSource {
    let syncSource: any ConversationSyncSource

    func sims() async -> [PlaceCallSim] {
        await syncSource.simOptions().map { PlaceCallSim(id: $0.id, name: $0.name) }
    }
}
