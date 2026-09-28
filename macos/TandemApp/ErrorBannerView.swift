import SwiftUI

/// Renders ``ErrorBannerViewModel``'s current ``ErrorBannerViewModel/message`` (E22-07,
/// invariant 5): plain `Text`/`Button` rather than an `.alert`, matching ``MenuBarContentView``'s
/// own reasoning -- macOS exposes SwiftUI `Text`/`Button` content more reliably to XCUITest than
/// composite controls on headless runners. Renders nothing while ``ErrorBannerViewModel/message``
/// is `nil` (before the first fail-closed event, or after "OK" is tapped).
struct ErrorBannerView: View {
    let viewModel: ErrorBannerViewModel

    var body: some View {
        if let message = viewModel.message {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .accessibilityIdentifier("failClosedBannerMessage")
                    .accessibilityLabel(message)

                Button("OK") { viewModel.dismiss() }
                    .accessibilityIdentifier("failClosedBannerOkButton")
                    .accessibilityLabel("OK")
            }
            .padding()
        }
    }
}
