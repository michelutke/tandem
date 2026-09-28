import SwiftUI

/// Renders ``LocalNetworkPermissionViewModel``'s denial banner (E21-03): nothing while
/// ``LocalNetworkPermissionViewModel/isDenied`` is `false`, else the exact explanation text and an
/// "Open System Settings" button -- matching ``MenuBarContentView``'s plain `Text`/`Button`
/// convention (reliable AXValue for XCUITest over composite controls).
struct LocalNetworkPermissionBannerView: View {
    let viewModel: LocalNetworkPermissionViewModel

    var body: some View {
        if viewModel.isDenied {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalNetworkPermissionViewModel.explanationText)
                    .accessibilityIdentifier("localNetworkDeniedExplanationLabel")
                    .accessibilityLabel(LocalNetworkPermissionViewModel.explanationText)

                Button(LocalNetworkPermissionViewModel.openSettingsButtonTitle) {
                    viewModel.openSettingsTapped()
                }
                .accessibilityIdentifier("openSystemSettingsButton")
                .accessibilityLabel(LocalNetworkPermissionViewModel.openSettingsButtonTitle)
            }
        }
    }
}
