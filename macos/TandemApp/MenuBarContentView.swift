import SwiftUI

/// Renders ``MenuBarViewModel``'s current state (E22-01): the connection label, and either the
/// "Pair phone…" action (no paired peer, UC-01) or the battery/network/signal row(s). Plain
/// `Text`/`Button` rather than `Label`/`Menu` -- macOS exposes SwiftUI `Text` content reliably as
/// AXValue for XCUITest, matching the existing `ScenarioView` convention, whereas composite
/// controls are less predictable on headless runners.
struct MenuBarContentView: View {
    let viewModel: MenuBarViewModel

    /// `nil` until a `DeviceStatus` has been received (E23-04) -- ``batteryText`` then falls back
    /// to ``MenuBarViewModel/batteryPlaceholder``, and the network/signal rows are omitted
    /// entirely.
    let deviceStatusViewModel: DeviceStatusViewModel?

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
                let batteryText = deviceStatusViewModel?.batteryText ?? MenuBarViewModel.batteryPlaceholder
                Text(batteryText)
                    .accessibilityIdentifier("batteryLabel")
                    .accessibilityLabel(batteryText)

                if let networkText = deviceStatusViewModel?.networkText {
                    Text(networkText)
                        .accessibilityIdentifier("networkLabel")
                        .accessibilityLabel(networkText)
                }

                if let signalBars = deviceStatusViewModel?.signalBars,
                   let signalAccessibilityValue = deviceStatusViewModel?.signalAccessibilityValue {
                    Text("\(signalBars)")
                        .accessibilityIdentifier("signalLabel")
                        .accessibilityValue(signalAccessibilityValue)
                }
            }
        }
        .padding()
    }
}
