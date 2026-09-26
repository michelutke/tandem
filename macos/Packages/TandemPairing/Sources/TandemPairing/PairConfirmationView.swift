import SwiftUI
import TandemDesign

/// The "Confirm" pairing-window screen (`docs/design/ui-spec.md` §5.1, mac-pairing-confirm):
/// lays out ``PairConfirmationViewModel``'s state with `TandemDesign` components. Deliberately
/// minimal and untested (the view model carries every rule this issue tests); no `#Preview` here
/// since a real view model needs a live `PairingWindow`/`PairingCandidateSink`/`TrustStore` this
/// package's main target has no fake for (`TandemTestSupport` is a test-target-only dependency).
public struct PairConfirmationView: View {
    private let viewModel: PairConfirmationViewModel

    public init(viewModel: PairConfirmationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassWindow {
            VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                TitleBlock(subject: viewModel.title, state: viewModel.bodyText)
                HStack(spacing: TandemSpacing.small) {
                    PillButton("Don't Pair", kind: .secondary) {
                        Task { await viewModel.dontPair() }
                    }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut(.defaultAction)

                    PillButton("Pair", kind: .primary) {
                        Task { await viewModel.pair() }
                    }
                }
            }
            .frame(width: 360)
        }
    }
}
