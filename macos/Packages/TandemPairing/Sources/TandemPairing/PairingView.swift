import SwiftUI
import TandemDesign

/// The "QR" pairing-window screen (`docs/design/ui-spec.md` §5.1, mac-pairing-qr /
/// mac-pairing-no-tries-left): lays out ``PairingViewModel``'s state with `TandemDesign`
/// components. Deliberately minimal and untested -- the view model carries every rule this issue
/// tests, matching ``PairConfirmationView``'s precedent. The `TimelineView` tick drives
/// ``PairingViewModel/tick()`` (real wall time in production) so the countdown re-renders and the
/// window auto-regenerates on plain expiry without this package ever touching the wall clock or a
/// bare sleep directly itself (E00-24 seam rule).
public struct PairingView: View {
    private let viewModel: PairingViewModel

    public init(viewModel: PairingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TimelineView(.periodic(from: .distantPast, by: 1)) { context in
            GlassWindow {
                content
            }
            .onAppear { viewModel.tick() }
            .onChange(of: context.date) { _, _ in viewModel.tick() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.attemptsExhausted {
            attemptsExhaustedContent
        } else {
            qrContent
        }
    }

    private var qrContent: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Pair.", state: "Scan with your phone.")
            DotQR(modules: viewModel.qrModules)
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: TandemSpacing.extraSmall) {
                    Text(Self.countdownText(seconds: viewModel.remainingSeconds))
                        .tandemTextStyle(TandemTypography.displayNumeral(size: 28))
                        .foregroundStyle(TandemColor.ink)
                    Text("left")
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: TandemSpacing.extraSmall) {
                    DotProgress(value: Double(viewModel.attemptsRemaining) / 3, dotCount: 3)
                    Text("\(viewModel.attemptsRemaining) tries")
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                }
            }
        }
        .frame(width: 360)
    }

    private var attemptsExhaustedContent: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Pair.", state: "Too many tries.", isAlert: true)
            Text(PairingViewModel.attemptsExhaustedMessage)
                .tandemTextStyle(TandemTypography.body())
                .foregroundStyle(TandemColor.ink2)
            PillButton("Regenerate") {
                viewModel.regenerate()
            }
        }
        .frame(width: 360)
    }

    private static func countdownText(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
