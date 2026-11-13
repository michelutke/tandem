import SwiftUI
import TandemDesign

/// The "Paired." pairing-window screen (`docs/design/ui-spec.md` §7.1, mac-pairing-paired): shown
/// once the owner's Pair click has committed trust, until "Done" closes the window.
public struct PairedView: View {
    private let stateText: String
    private let onDone: () -> Void

    public init(stateText: String, onDone: @escaping () -> Void) {
        self.stateText = stateText
        self.onDone = onDone
    }

    public var body: some View {
        GlassWindow {
            VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                TitleBlock(subject: "Paired.", state: stateText)
                Circle()
                    .fill(TandemColor.signal)
                    .frame(width: 44, height: 44)
                    .padding(.vertical, TandemSpacing.small)
                    .accessibilityHidden(true)
                PairingActionRows(actions: [
                    PairingAction(title: "Done", shortcut: .defaultAction, action: onDone)
                ])
            }
            .frame(width: 360)
        }
    }
}
