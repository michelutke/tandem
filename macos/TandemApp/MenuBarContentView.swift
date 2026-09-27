import SwiftUI

/// Renders ``MenuBarViewModel``'s current state (E22-01): the connection label, and either the
/// "Pair phone…" action (no paired peer, UC-01) or the battery placeholder row. Plain `Text`/
/// `Button` rather than `Label`/`Menu` -- macOS exposes SwiftUI `Text` content reliably as AXValue
/// for XCUITest, matching the existing `ScenarioView` convention, whereas composite controls are
/// less predictable on headless runners.
struct MenuBarContentView: View {
    let viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.label)
                .accessibilityIdentifier("menuBarStateLabel")
                .accessibilityLabel(viewModel.label)

            if viewModel.showsPairPhoneMenuItem {
                Button("Pair phone…") {}
                    .accessibilityIdentifier("pairPhoneMenuItem")
                    .accessibilityLabel("Pair phone…")
            } else {
                Text(MenuBarViewModel.batteryPlaceholder)
                    .accessibilityIdentifier("batteryLabel")
                    .accessibilityLabel(MenuBarViewModel.batteryPlaceholder)
            }
        }
        .padding()
    }
}
