import SwiftUI
import TandemDesign

/// The "QR" pairing-window screen (`docs/design/ui-spec.md` §7.1, mac-pairing-qr /
/// mac-pairing-expired / mac-pairing-no-tries-left): lays out ``PairingViewModel``'s state with
/// `TandemDesign` components. Deliberately minimal and untested -- the view model carries every
/// rule this issue tests, matching ``PairConfirmationView``'s precedent. The `TimelineView` tick
/// drives ``PairingViewModel/tick()`` (real wall time in production) so the countdown re-renders
/// without this package ever touching the wall clock or a bare sleep directly itself (E00-24
/// seam rule).
public struct PairingView: View {
    private let viewModel: PairingViewModel
    private let onCancel: () -> Void

    public init(viewModel: PairingViewModel, onCancel: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onCancel = onCancel
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
            closedContent(
                state: "Too many tries.",
                isAlert: true,
                numeral: "\(viewModel.attemptsRemaining)/3",
                numeralColor: TandemColor.alert
            )
        } else if viewModel.isExpired {
            closedContent(state: "Code expired.", isAlert: false, numeral: "0:00", numeralColor: TandemColor.ink2)
        } else if viewModel.isManual {
            manualContent
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
                    countdown
                    Text("left")
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                }
                Spacer()
                tries
            }
        }
        .frame(width: 360)
    }

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Pair.", state: "Enter this Mac on your phone.")
            Text(viewModel.manualAddressText ?? "No network address")
                .tandemTextStyle(TandemTypography.displayNumeral(size: 28))
                .foregroundStyle(TandemColor.ink)
            Text("On your phone choose Pair without camera, then enter this address.")
                .tandemTextStyle(TandemTypography.body())
                .foregroundStyle(TandemColor.ink2)
            HStack {
                countdown
                Spacer()
                tries
            }
        }
        .frame(width: 360)
    }

    private func closedContent(
        state: String,
        isAlert: Bool,
        numeral: String,
        numeralColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            TitleBlock(subject: "Pair.", state: state, isAlert: isAlert)
            Text(numeral)
                .tandemTextStyle(TandemTypography.displayNumeral(size: 64))
                .foregroundStyle(numeralColor)
                .padding(.vertical, TandemSpacing.small)
            PairingActionRows(actions: [
                PairingAction(title: "New code", shortcut: .defaultAction) { viewModel.regenerate() },
                PairingAction(title: "Cancel", shortcut: .cancelAction, action: onCancel)
            ])
        }
        .frame(width: 360)
    }

    private var countdown: some View {
        Text(Self.countdownText(seconds: viewModel.remainingSeconds))
            .tandemTextStyle(TandemTypography.displayNumeral(size: 28))
            .foregroundStyle(Self.countdownColor(seconds: viewModel.remainingSeconds))
    }

    private var tries: some View {
        VStack(alignment: .trailing, spacing: TandemSpacing.extraSmall) {
            DotProgress(value: Double(viewModel.attemptsRemaining) / 3, dotCount: 3, leadsWithSignal: false)
            Text(PairingViewModel.attemptsLabel(attemptsRemaining: viewModel.attemptsRemaining))
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
        }
    }

    private static func countdownText(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func countdownColor(seconds: Int) -> Color {
        switch PairingCountdownTone.tone(forRemainingSeconds: seconds) {
        case .normal: TandemColor.ink
        case .grey: TandemColor.ink2
        case .urgent: TandemColor.alert
        }
    }
}
