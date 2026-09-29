import SwiftUI

/// Renders ``QuickActionsViewModel``'s four actions (E22-02): plain `Text`/`Button` rather than
/// `Menu`, matching ``MenuBarContentView``'s own reasoning -- macOS exposes SwiftUI `Button`
/// content more reliably to XCUITest than composite controls on headless runners. A sibling view
/// to ``MenuBarContentView`` rather than added to it, so that view stays focused on connection
/// state alone.
struct QuickActionsView: View {
    let viewModel: QuickActionsViewModel

    /// Drives the "Find Phone"/"Stop Ringing" label (E23-07) -- the only one of the four actions
    /// whose label changes at runtime, so it gets its own button rather than sharing
    /// ``actionButton(_:identifier:)``'s static ``QuickActionsViewModel/Action/label``.
    let findPhoneViewModel: FindPhoneViewModel

    /// Drives the "Not sent: protected item"/size-hint text shown under "Push Clipboard" (E31-11)
    /// when a push doesn't send.
    let pushClipboardViewModel: PushClipboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton(.sendFile, identifier: "sendFileMenuItem")
            actionButton(.pushClipboard, identifier: "pushClipboardMenuItem")
            pushClipboardStatusLabel
            findPhoneButton
            actionButton(.mirror, identifier: "mirrorPhoneMenuItem")
        }
    }

    @ViewBuilder
    private var pushClipboardStatusLabel: some View {
        if let statusMessage = pushClipboardViewModel.statusMessage {
            Text(statusMessage)
                .accessibilityIdentifier("pushClipboardStatusLabel")
        }
    }

    private var findPhoneButton: some View {
        Button(findPhoneViewModel.label) { viewModel.select(.findPhone) }
            .disabled(!viewModel.isConnected)
            .accessibilityIdentifier("findPhoneMenuItem")
            .accessibilityLabel(findPhoneViewModel.label)
    }

    private func actionButton(_ action: QuickActionsViewModel.Action, identifier: String) -> some View {
        Button(action.label) { viewModel.select(action) }
            .disabled(!viewModel.isConnected)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(action.label)
    }
}
