import FeatureCalls
import SwiftUI
import TandemDesign

/// The menu bar's Hang Up quick action (E52-06): shown only while ``CallAlertViewModel`` reports an
/// `ACTIVE` call, and removed again once the call `ENDED`.
struct CallHangUpView: View {
    let viewModel: CallAlertViewModel

    var body: some View {
        if viewModel.showsHangUp {
            PillButton("Hang up", kind: .destructive) {
                Task { await viewModel.hangUp() }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("hangUpMenuItem")
            .accessibilityLabel("Hang up")
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
