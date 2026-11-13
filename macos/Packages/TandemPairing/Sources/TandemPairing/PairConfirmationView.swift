import SwiftUI
import TandemDesign

/// The "Confirm" pairing-window screen (`docs/design/ui-spec.md` §7.1, mac-pairing-confirm):
/// lays out ``PairConfirmationViewModel``'s state with `TandemDesign` components. Deliberately
/// minimal and untested (the view model carries every rule this issue tests); no `#Preview` here
/// since a real view model needs a live `PairingWindow`/`PairingCandidateSink`/`TrustStore` this
/// package's main target has no fake for (`TandemTestSupport` is a test-target-only dependency).
/// Return and Escape both map to "Don't pair" (ui-spec §9 "Default to safety").
public struct PairConfirmationView: View {
    private let viewModel: PairConfirmationViewModel
    private let onPaired: () -> Void

    public init(viewModel: PairConfirmationViewModel, onPaired: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onPaired = onPaired
    }

    public var body: some View {
        GlassWindow {
            VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                TitleBlock(subject: viewModel.subject, state: viewModel.stateText)
                Text(viewModel.groupedCode)
                    .tandemTextStyle(TandemTypography.displayNumeral(size: 64))
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.vertical, TandemSpacing.small)
                PairingActionRows(actions: [
                    PairingAction(title: "Don't pair", trailingMeta: "default", shortcut: .defaultAction) {
                        Task { await viewModel.dontPair() }
                    },
                    PairingAction(title: "Pair") {
                        Task {
                            await viewModel.pair()
                            if viewModel.isResolved && !viewModel.didFailToPair { onPaired() }
                        }
                    }
                ])
            }
            .frame(width: 360)
            .keyboardShortcutButton(.cancelAction) { Task { await viewModel.dontPair() } }
        }
    }
}
