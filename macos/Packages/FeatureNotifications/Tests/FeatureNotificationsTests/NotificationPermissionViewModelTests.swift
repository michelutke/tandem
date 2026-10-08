import Foundation
import Testing
@testable import FeatureNotifications

@MainActor
@Suite struct NotificationPermissionViewModelTests {
    @Test func viewModel_denied_showsHint() {
        let viewModel = NotificationPermissionViewModel(openURL: { _ in })

        viewModel.update(.denied)

        #expect(viewModel.isDenied)
        #expect(NotificationPermissionViewModel.hintText == "Notifications are off in System Settings.")
    }

    @Test func viewModel_authorizedAfterDenied_hidesHint() {
        let viewModel = NotificationPermissionViewModel(openURL: { _ in })
        viewModel.update(.denied)

        viewModel.update(.authorized)

        #expect(!viewModel.isDenied)
    }

    @Test func viewModel_unavailable_doesNotShowHint() {
        let viewModel = NotificationPermissionViewModel(openURL: { _ in })

        viewModel.update(.unavailable)

        #expect(!viewModel.isDenied)
    }

    @Test func viewModel_openSettingsTapped_opensNotificationsPane() {
        var opened: [URL] = []
        let viewModel = NotificationPermissionViewModel(openURL: { opened.append($0) })

        viewModel.openSettingsTapped()

        let expected = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        #expect(opened.map(\.absoluteString) == [expected])
    }
}
