import SwiftUI

/// Renders ``QuickActionsViewModel``'s four actions (E22-02): plain `Text`/`Button` rather than
/// `Menu`, matching ``MenuBarContentView``'s own reasoning -- macOS exposes SwiftUI `Button`
/// content more reliably to XCUITest than composite controls on headless runners. A sibling view
/// to ``MenuBarContentView`` rather than added to it, so that view stays focused on connection
/// state alone.
struct QuickActionsView: View {
    let viewModel: QuickActionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton(.sendFile, identifier: "sendFileMenuItem")
            actionButton(.pushClipboard, identifier: "pushClipboardMenuItem")
            actionButton(.findPhone, identifier: "findPhoneMenuItem")
            actionButton(.mirror, identifier: "mirrorPhoneMenuItem")
        }
    }

    private func actionButton(_ action: QuickActionsViewModel.Action, identifier: String) -> some View {
        Button(action.label) { viewModel.select(action) }
            .disabled(!viewModel.isConnected)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(action.label)
    }
}
