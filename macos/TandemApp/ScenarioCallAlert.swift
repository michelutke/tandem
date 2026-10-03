#if DEBUG
import FeatureCalls
import Foundation
import SwiftUI
import TandemCrypto
import TandemProtocol
import TandemStore

extension ScenarioView {
    /// A call already `ACTIVE` on the phone (E52-06), so the menu bar's Hang Up item shows without
    /// a phone.
    @MainActor
    static func makeIncomingCallActiveView() -> some View {
        IncomingCallActiveScenarioView()
    }
}

private actor SilentCallAlertPresenter: CallAlertPresenter {
    nonisolated let responses = AsyncStream<CallAlertResponse> { _ in }

    func present(callId: String, title: String, body: String) async {}

    func remove(callId: String) async {}
}

private struct IncomingCallActiveScenarioView: View {
    @State private var viewModel = IncomingCallActiveScenarioView.makeViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CallHangUpView(viewModel: viewModel)
        }
        .task {
            var event = Tandem_V1_CallEvent()
            event.callID = "scenario-call"
            event.direction = .incoming
            event.state = .active
            await viewModel.handle(event)
        }
    }

    private static func makeViewModel() -> CallAlertViewModel {
        // swiftlint:disable:next force_try
        let peer = try! SpkiFingerprint(bytes: Data(repeating: 0x01, count: SpkiFingerprint.byteCount))
        return CallAlertViewModel(
            presenter: SilentCallAlertPresenter(),
            session: FakeTandemSession(),
            contacts: InMemoryContactsStore(),
            peer: peer
        )
    }
}
#endif
