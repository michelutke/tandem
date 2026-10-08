import Foundation
@preconcurrency import UserNotifications

/// Whether the system will show this app's notifications; asks the user the first time.
public protocol NotificationAuthorizing: Sendable {
    func isAuthorized() async -> Bool
}

/// What an in-app banner shows. Already-sanitized strings from the notification request.
public struct BannerContent: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let subtitle: String
    public let body: String

    public init(identifier: String, title: String, subtitle: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}

/// An in-app banner that needs no system notification permission.
public protocol NotificationBannerPresenting: Sendable {
    func show(_ banner: BannerContent) async
    func remove(identifier: String) async
}

/// `UNUserNotificationCenter` authorization: requests `.alert` and `.sound` once when undecided.
/// A build the system refuses to authorize (unsigned) or a denial reads as not authorized.
public actor UNNotificationAuthorization: NotificationAuthorizing {
    private let center: UNUserNotificationCenter
    private var requested = false

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            guard !requested else { return false }
            requested = true
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if !granted { NotificationsLog.event("denied") }
            return granted
        default:
            return false
        }
    }
}

/// Presents through the system when it is authorized and accepts the request, otherwise through
/// an in-app banner, so mirrored notifications still show in a build the system will not
/// deliver for.
public final class FallbackNotificationPresenter: NotificationPresenter, Sendable {
    private let system: any NotificationPresenter
    private let authorization: any NotificationAuthorizing
    private let banners: any NotificationBannerPresenting

    public init(
        system: any NotificationPresenter,
        authorization: any NotificationAuthorizing,
        banners: any NotificationBannerPresenting
    ) {
        self.system = system
        self.authorization = authorization
        self.banners = banners
    }

    public var responses: AsyncStream<NotificationResponseEvent> { system.responses }

    @discardableResult
    public func add(_ request: UNNotificationRequest) async -> Bool {
        if await authorization.isAuthorized(), await system.add(request) {
            NotificationsLog.event("presented via system")
            return true
        }
        NotificationsLog.event("presented via fallback")
        await banners.show(
            BannerContent(
                identifier: request.identifier,
                title: request.content.title,
                subtitle: request.content.subtitle,
                body: request.content.body
            )
        )
        return true
    }

    public func removeDelivered(identifiers: [String]) async {
        await system.removeDelivered(identifiers: identifiers)
        for identifier in identifiers {
            await banners.remove(identifier: identifier)
        }
    }

    public func setCategories(_ categories: Set<UNNotificationCategory>) async {
        await system.setCategories(categories)
    }
}
