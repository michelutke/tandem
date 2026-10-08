import SwiftUI
import TandemDesign

/// The main window's Transfers section (ui-spec §7.1): in-flight transfers with percent, dot
/// progress and speed, then the earlier list.
public struct TransfersSectionView: View {
    private let center: TransferProgressCenter
    private let onSendFile: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    public init(center: TransferProgressCenter, onSendFile: @escaping () -> Void) {
        self.center = center
        self.onSendFile = onSendFile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            HStack(alignment: .top) {
                TitleBlock(subject: "Transfers.", state: Self.stateText(activeCount: center.rows.count), size: 26)
                Spacer()
                PillButton("Send file", kind: .secondary, action: onSendFile)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("sendFileButton")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(center.rows, id: \.id) { row in
                        activeRow(row)
                    }
                    if !center.earlier.isEmpty {
                        Text("Earlier")
                            .tandemTextStyle(TandemTypography.meta())
                            .foregroundStyle(TandemColor.ink2)
                            .padding(.top, TandemSpacing.medium)
                            .padding(.bottom, TandemSpacing.small)
                        ForEach(center.earlier) { transfer in
                            earlierRow(transfer)
                        }
                    }
                }
            }
            .accessibilityIdentifier("transferList")
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "1 in progress." / "Nothing in progress." (ui-spec §7.1).
    public static func stateText(activeCount: Int) -> String {
        activeCount == 0 ? "Nothing in progress." : "\(activeCount) in progress."
    }

    private func activeRow(_ row: TransferProgressViewModel) -> some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .tandemTextStyle(TandemTypography.rowTitle(size: 18))
                        .foregroundStyle(TandemColor.ink)
                    HStack(spacing: TandemSpacing.small) {
                        Text(row.isCancelled ? "Cancelled" : "\(row.bytesText) · \(row.speedText)")
                            .tandemTextStyle(TandemTypography.meta())
                            .foregroundStyle(TandemColor.ink2)
                            .accessibilityIdentifier("transferSpeed")
                        if !row.isCancelled {
                            Button("Cancel") { Task { await row.cancel() } }
                                .buttonStyle(.plain)
                                .tandemTextStyle(TandemTypography.meta())
                                .foregroundStyle(TandemColor.ink)
                                .accessibilityIdentifier("transferCancel")
                        }
                    }
                }
                Spacer()
                if !row.isCancelled {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(row.progress.percent)")
                            .tandemTextStyle(TandemTypography.displayNumeral(size: 44))
                            .foregroundStyle(TandemColor.ink)
                            .accessibilityIdentifier("transferPercent")
                        Text("%")
                            .tandemTextStyle(TandemTypography.meta())
                            .foregroundStyle(TandemColor.ink2)
                    }
                }
            }
            DotProgress(value: Double(row.progress.percent) / 100, dotCount: 40)
        }
        .padding(.bottom, TandemSpacing.large)
        .overlay(alignment: .bottom) { hairline }
    }

    private func earlierRow(_ transfer: EarlierTransfer) -> some View {
        HStack {
            Text(transfer.name)
                .tandemTextStyle(TandemTypography.body(size: 15))
                .foregroundStyle(TandemColor.ink)
                .lineLimit(1)
            Spacer()
            Text(transfer.sizeText)
                .tandemTextStyle(TandemTypography.metaMono())
                .foregroundStyle(TandemColor.ink2)
            Text(transfer.timeText())
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, TandemSpacing.medium)
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle().fill(TandemColor.line(increasedContrast: contrast == .increased)).frame(height: 1)
    }
}
