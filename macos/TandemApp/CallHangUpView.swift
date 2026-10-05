import FeatureCalls
import SwiftUI

/// The menu bar's Hang Up quick action (E52-06): shown only while ``CallAlertViewModel`` reports an
/// `ACTIVE` call, and removed again once the call `ENDED`.
struct CallHangUpView: View {
    let viewModel: CallAlertViewModel

    var body: some View {
        if viewModel.showsHangUp {
            Button("Hang Up") {
                Task { await viewModel.hangUp() }
            }
            .accessibilityIdentifier("hangUpMenuItem")
            .accessibilityLabel("Hang Up")
        }
    }
}

/// ``CallHangUpView`` over whichever session's call alerts are attached (E22-13).
struct ActiveCallHangUpView: View {
    let activeCall: ActiveCallAlert

    var body: some View {
        if let viewModel = activeCall.viewModel {
            CallHangUpView(viewModel: viewModel)
        }
    }
}
