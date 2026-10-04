#if DEBUG
import FeatureMirror
import SwiftUI
@testable import TandemProtocol

extension ScenarioView {
    static func makeMirrorDeclinedView() -> some View {
        MirrorDeclinedScenarioView()
    }
}

private struct MirrorDeclinedScenarioView: View {
    @State private var viewModel = MirrorRequestViewModel(session: MirrorDeclinedScenarioView.session)

    private static let session = FakeTandemSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let statusText = viewModel.statusText {
                Text(statusText)
                    .accessibilityIdentifier("mirrorStatusLabel")
            }
        }
        .task {
            await viewModel.start()
            viewModel.request()
            await Self.session.inject(
                InboundFrame(channel: .control, seq: 0, ack: 0, payload: .mirrorDeclined(Tandem_V1_MirrorDeclined())))
        }
    }
}
#endif
