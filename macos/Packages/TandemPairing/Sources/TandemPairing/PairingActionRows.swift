import SwiftUI
import TandemDesign

/// One numbered row below a pairing screen's hairline ("01 New code").
struct PairingAction {
    let title: String
    var trailingMeta: String?
    var shortcut: KeyboardShortcut?
    let action: () -> Void
}

/// The hairline plus numbered rows shared by the pairing window's Confirm, Expired, No tries left
/// and Paired screens. The first row is the highlighted default.
struct PairingActionRows: View {
    let actions: [PairingAction]

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
                .padding(.bottom, TandemSpacing.small)
            ForEach(Array(actions.enumerated()), id: \.offset) { offset, action in
                NumberedActionRow(
                    index: offset + 1,
                    title: action.title,
                    trailingMeta: action.trailingMeta,
                    isSelected: offset == 0,
                    verticalPadding: TandemSpacing.small + TandemSpacing.extraSmall,
                    horizontalPadding: TandemSpacing.small,
                    action: action.action
                )
                .keyboardShortcut(action.shortcut)
            }
        }
    }
}
