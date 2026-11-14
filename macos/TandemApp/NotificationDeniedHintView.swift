import AppKit
import FeatureNotifications
import SwiftUI
import TandemDesign

extension NotificationPermissionViewModel {
    /// Fed by the notification presenter; read by the popover and the Settings Notifications tab.
    @MainActor static let shared = NotificationPermissionViewModel(openURL: { NSWorkspace.shared.open($0) })

    @Sendable static func report(_ state: NotificationAuthorizationState) async {
        await MainActor.run { shared.update(state) }
    }
}

/// The "Notifications are off in System Settings." hint with a button to the Notifications pane;
/// nothing while notifications are not explicitly denied.
struct NotificationDeniedHintView: View {
    let viewModel: NotificationPermissionViewModel

    var body: some View {
        if viewModel.isDenied {
            VStack(alignment: .leading, spacing: TandemSpacing.small) {
                Text(NotificationPermissionViewModel.hintText)
                    .tandemTextStyle(TandemTypography.body(size: 13))
                    .foregroundStyle(TandemColor.ink2)
                    .accessibilityIdentifier("notificationsDeniedHintLabel")
                PillButton(NotificationPermissionViewModel.openSettingsButtonTitle, kind: .secondary) {
                    viewModel.openSettingsTapped()
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("openNotificationsSettingsButton")
            }
        }
    }
}
