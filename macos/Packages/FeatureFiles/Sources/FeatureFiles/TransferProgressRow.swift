import SwiftUI
import TandemDesign

/// One transfer row (ui-spec §2 hairline rows): name, percent and speed, and a Cancel button.
/// Plain `Text`/`Button` so XCUITest reads the values reliably, like the other menu bar views.
public struct TransferProgressRow: View {
    let viewModel: TransferProgressViewModel

    @Environment(\.colorSchemeContrast) private var contrast

    public init(viewModel: TransferProgressViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: TandemSpacing.medium) {
            VStack(alignment: .leading, spacing: TandemSpacing.extraSmall) {
                Text(viewModel.name)
                    .tandemTextStyle(TandemTypography.rowTitle())
                    .foregroundStyle(TandemColor.ink)
                if viewModel.isCancelled {
                    Text("Cancelled")
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                        .accessibilityIdentifier("transferState")
                } else {
                    Text(viewModel.speedText)
                        .tandemTextStyle(TandemTypography.metaMono())
                        .foregroundStyle(TandemColor.ink2)
                        .accessibilityIdentifier("transferSpeed")
                }
            }
            Spacer()
            if !viewModel.isCancelled {
                Text(viewModel.percentText)
                    .tandemTextStyle(TandemTypography.metaMono())
                    .foregroundStyle(TandemColor.ink)
                    .accessibilityIdentifier("transferPercent")
                    .accessibilityLabel(viewModel.percentText)
                Button("Cancel") { Task { await viewModel.cancel() } }
                    .accessibilityIdentifier("transferCancel")
            }
        }
        .padding(.vertical, TandemSpacing.rowVertical)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TandemColor.line(increasedContrast: contrast == .increased))
                .frame(height: 1)
        }
    }
}
