import Foundation
import Observation

/// Tells the user when notifications are off in System Settings (an explicit denial), with a button
/// to the Notifications pane. Shown in the menu bar popover and the Settings Notifications tab.
@MainActor
@Observable
public final class NotificationPermissionViewModel {
    public static let hintText = "Notifications are off in System Settings."
    public static let openSettingsButtonTitle = "Open Notifications settings"

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    public private(set) var isDenied = false

    private let openURL: @MainActor (URL) -> Void

    public init(openURL: @escaping @MainActor (URL) -> Void) {
        self.openURL = openURL
    }

    public func update(_ state: NotificationAuthorizationState) {
        isDenied = state == .denied
    }

    public func openSettingsTapped() {
        openURL(Self.settingsURL)
    }
}
