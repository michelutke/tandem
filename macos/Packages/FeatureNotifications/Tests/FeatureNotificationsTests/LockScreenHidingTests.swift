import FeatureNotifications
import Foundation
import Testing
import TandemCrypto
@testable import TandemProtocol

@Suite struct LockScreenHidingTests {
    private static func peer() throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: 0x07, count: 32))
    }

    private static func posted(key: String = "k1") -> Tandem_V1_NotificationPosted {
        var posted = Tandem_V1_NotificationPosted()
        posted.key = key
        posted.packageName = "com.example.chat"
        posted.title = "Alice"
        posted.text = "secret body"
        posted.messagingStyleSenders = ["Alice"]
        return posted
    }

    private static func makeCoordinator(
        presenter: RecordingNotificationPresenter,
        lockState: FakeScreenLockState,
        setting: FakeHideWhenLockedSetting
    ) -> NotificationPresentationCoordinator {
        NotificationPresentationCoordinator(
            presenter: presenter,
            screenLockState: lockState,
            hidesContentWhenLocked: { setting.isEnabled }
        )
    }

    @Test func lockScreenHiding_enabledAndLocked_titleAppNameBodyEmpty() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = Self.makeCoordinator(
            presenter: presenter,
            lockState: FakeScreenLockState(isLocked: true),
            setting: FakeHideWhenLockedSetting(enabled: true)
        )

        await coordinator.present(Self.posted(), from: try Self.peer())

        let contents = await presenter.addedContents
        #expect(contents == [.init(title: "com.example.chat", subtitle: "", body: "")])
    }

    @Test func lockScreenHiding_enabledAndUnlocked_fullTitleAndBody() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = Self.makeCoordinator(
            presenter: presenter,
            lockState: FakeScreenLockState(isLocked: false),
            setting: FakeHideWhenLockedSetting(enabled: true)
        )

        await coordinator.present(Self.posted(), from: try Self.peer())

        let contents = await presenter.addedContents
        #expect(contents == [.init(title: "Alice", subtitle: "com.example.chat", body: "Alice: secret body")])
    }

    @Test func lockScreenHiding_disabledAndLocked_fullTitleAndBody() async throws {
        let presenter = RecordingNotificationPresenter()
        let coordinator = Self.makeCoordinator(
            presenter: presenter,
            lockState: FakeScreenLockState(isLocked: true),
            setting: FakeHideWhenLockedSetting(enabled: false)
        )

        await coordinator.present(Self.posted(), from: try Self.peer())

        let contents = await presenter.addedContents
        #expect(contents == [.init(title: "Alice", subtitle: "com.example.chat", body: "Alice: secret body")])
    }

    @Test func lockScreenHiding_lockedThenUnlocked_noRepost() async throws {
        let presenter = RecordingNotificationPresenter()
        let lockState = FakeScreenLockState(isLocked: true)
        let coordinator = Self.makeCoordinator(
            presenter: presenter,
            lockState: lockState,
            setting: FakeHideWhenLockedSetting(enabled: true)
        )

        await coordinator.present(Self.posted(), from: try Self.peer())
        lockState.setLocked(false)
        await Task.yield()

        let identifiers = await presenter.addedIdentifiers
        #expect(identifiers == ["k1"])
    }

    @Test func lockScreenHiding_toggledOn_nextPostHiddenWithZeroReconnects() async throws {
        let presenter = RecordingNotificationPresenter()
        let setting = FakeHideWhenLockedSetting(enabled: false)
        let coordinator = Self.makeCoordinator(
            presenter: presenter,
            lockState: FakeScreenLockState(isLocked: true),
            setting: setting
        )

        await coordinator.present(Self.posted(key: "k1"), from: try Self.peer())
        setting.set(true)
        await coordinator.present(Self.posted(key: "k2"), from: try Self.peer())

        let contents = await presenter.addedContents
        #expect(contents.map(\.body) == ["Alice: secret body", ""])
        #expect(contents.map(\.title) == ["Alice", "com.example.chat"])
    }

    @Test func screenLockState_screenIsLockedNotification_reportsLocked() async {
        let center = NotificationCenter()
        let state = DistributedScreenLockState(notificationCenter: center)
        #expect(state.isLocked == false)

        center.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        #expect(state.isLocked == true)

        center.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        #expect(state.isLocked == false)
    }
}
