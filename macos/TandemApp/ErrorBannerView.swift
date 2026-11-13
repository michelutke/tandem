import SwiftUI
import TandemDesign

/// Renders ``ErrorBannerViewModel``'s current ``ErrorBannerViewModel/message`` as the main window's
/// trust-error banner (E22-07, invariant 5; ui-spec §8 "Trust error banner, sections disabled"):
/// an alert-tinted block with the red title, the exact message and the next step -- "Pair again"
/// and "Unpair" for a key problem, "Check for update" for a version mismatch. Plain `Text` and
/// buttons rather than an `.alert`, since macOS exposes them more reliably to XCUITest on headless
/// runners. Renders nothing while ``ErrorBannerViewModel/message`` is `nil`; it goes away only once
/// the session is ready again.
struct ErrorBannerView: View {
    let viewModel: ErrorBannerViewModel
    var onPairAgain: () -> Void = {}
    var onUnpair: () -> Void = {}
    var onCheckForUpdate: () -> Void = {}

    var body: some View {
        if let message = viewModel.message {
            VStack(alignment: .leading, spacing: TandemSpacing.small) {
                Text(viewModel.title)
                    .tandemTextStyle(TandemTypography.rowTitle(size: 17))
                    .foregroundStyle(TandemColor.alert)
                    .accessibilityIdentifier("failClosedBannerTitle")
                Text(message)
                    .tandemTextStyle(TandemTypography.body())
                    .foregroundStyle(TandemColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("failClosedBannerMessage")
                    .accessibilityLabel(message)
                actions
            }
            .padding(TandemSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TandemColor.alert.opacity(0.08))
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: TandemSpacing.small) {
            if viewModel.closeCode == .versionMismatch {
                PillButton("Check for update", action: onCheckForUpdate)
                    .accessibilityIdentifier("failClosedBannerUpdateButton")
            } else {
                PillButton("Pair again", action: onPairAgain)
                    .accessibilityIdentifier("failClosedBannerPairAgainButton")
                PillButton("Unpair", kind: .secondary, action: onUnpair)
                    .accessibilityIdentifier("failClosedBannerUnpairButton")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
