import SwiftUI
import TandemDesign

/// The Mac main window's Devices screen (E14-14, `docs/design/ui-spec.md` §7.1): lays out
/// ``PairedDevicesViewModel``'s rows with `TandemDesign` components. Deliberately minimal and
/// untested (the view model carries every rule this issue tests, the same split as
/// ``PairConfirmationView``): a hairline row per paired device with its relative last-seen and a
/// destructive "Revoke" pill, and a ``GlassSheet`` confirmation before a revoke is sent.
public struct PairedDevicesView: View {
    @Bindable private var viewModel: PairedDevicesViewModel

    @Environment(\.colorSchemeContrast) private var contrast

    public init(viewModel: PairedDevicesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.rows) { row in
                    deviceRow(row)
                }
            }

            GlassSheet(isPresented: viewModel.pendingRevoke != nil) {
                if let pendingRevoke = viewModel.pendingRevoke {
                    VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                        TitleBlock(
                            subject: "Revoke \(pendingRevoke.displayName)?",
                            state: "It will need to pair again."
                        )
                        PillButton("Revoke", kind: .destructive) {
                            viewModel.confirmRevoke()
                        }
                        PillButton("Cancel", kind: .secondary) {
                            viewModel.cancelRevoke()
                        }
                    }
                    .frame(width: 280)
                }
            }
        }
    }

    private func deviceRow(_ row: PairedDevicesViewModel.Row) -> some View {
        HStack(spacing: TandemSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .tandemTextStyle(TandemTypography.rowTitle())
                    .foregroundStyle(TandemColor.ink)
                Text(row.lastSeenText)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
            }
            Spacer()
            PillButton("Revoke", kind: .destructive) {
                viewModel.requestRevoke(row)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, TandemSpacing.rowVertical)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TandemColor.line(increasedContrast: contrast == .increased))
                .frame(height: 1)
        }
    }
}
