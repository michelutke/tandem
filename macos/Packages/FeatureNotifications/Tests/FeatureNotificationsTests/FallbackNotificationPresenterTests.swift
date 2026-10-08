import FeatureNotifications
import Foundation
import Synchronization
import Testing
import TandemCrypto
@testable import TandemProtocol

private struct StubAuthorization: NotificationAuthorizing {
    let authorized: Bool
    func isAuthorized() async -> Bool { authorized }
}

private final class RecordingBanners: NotificationBannerPresenting {
    private let state = Mutex<(shown: [BannerContent], removed: [String])>(([], []))

    var shown: [BannerContent] { state.withLock { $0.shown } }
    var removed: [String] { state.withLock { $0.removed } }

    func show(_ banner: BannerContent) async { state.withLock { $0.shown.append(banner) } }
    func remove(identifier: String) async { state.withLock { $0.removed.append(identifier) } }
}

private func posted(key: String = "k1") -> Tandem_V1_NotificationPosted {
    var posted = Tandem_V1_NotificationPosted()
    posted.key = key
    posted.packageName = "com.example.chat"
    posted.title = "Ada"
    posted.text = "hello"
    return posted
}

@Suite struct FallbackNotificationPresenterTests {
    // swiftlint:disable:next force_try
    private let peer = try! SpkiFingerprint(bytes: Data(repeating: 9, count: 32))

    @Test func fallbackPresenter_authorized_presentsThroughSystemOnly() async {
        let system = RecordingNotificationPresenter()
        let banners = RecordingBanners()
        let presenter = FallbackNotificationPresenter(
            system: system, authorization: StubAuthorization(authorized: true), banners: banners
        )
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)

        await coordinator.present(posted(), from: peer)

        #expect(await system.addedIdentifiers == ["k1"])
        #expect(banners.shown.isEmpty)
    }

    @Test func fallbackPresenter_notAuthorized_postedNotificationShownAsBanner() async {
        let system = RecordingNotificationPresenter()
        let banners = RecordingBanners()
        let presenter = FallbackNotificationPresenter(
            system: system, authorization: StubAuthorization(authorized: false), banners: banners
        )
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)

        await coordinator.present(posted(), from: peer)

        #expect(await system.addedIdentifiers.isEmpty)
        #expect(banners.shown.map(\.identifier) == ["k1"])
        #expect(banners.shown.first?.title == "Ada")
        #expect(banners.shown.first?.body == "hello")
    }

    @Test func fallbackPresenter_authorizedButSystemRefuses_shownAsBanner() async {
        let system = RecordingNotificationPresenter()
        await system.setAcceptsRequests(false)
        let banners = RecordingBanners()
        let presenter = FallbackNotificationPresenter(
            system: system, authorization: StubAuthorization(authorized: true), banners: banners
        )
        let coordinator = NotificationPresentationCoordinator(presenter: presenter)

        await coordinator.present(posted(), from: peer)

        #expect(banners.shown.map(\.identifier) == ["k1"])
    }

    @Test func fallbackPresenter_removeDelivered_clearsSystemAndBanner() async {
        let system = RecordingNotificationPresenter()
        let banners = RecordingBanners()
        let presenter = FallbackNotificationPresenter(
            system: system, authorization: StubAuthorization(authorized: false), banners: banners
        )

        await presenter.removeDelivered(identifiers: ["k1"])

        #expect(await system.removedIdentifierBatches == [["k1"]])
        #expect(banners.removed == ["k1"])
    }
}
