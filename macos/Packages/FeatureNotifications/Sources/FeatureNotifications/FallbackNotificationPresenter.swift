import Foundation
@preconcurrency import UserNotifications

/// Whether the system will show this app's notifications.
public enum NotificationAuthorizationState: Sendable, Equatable {
    case authorized
    /// The user explicitly refused notifications; an in-app banner would override that choice.
    case denied
    /// The system cannot decide or deliver (unsigned build, request failure, no center).
    case unavailable
}

public protocol NotificationAuthorizing: Sendable {
    /// The current state; asks the user the first time when undecided.
    func state() async -> NotificationAuthorizationState
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
/// An explicit refusal reads as ``NotificationAuthorizationState/denied``; a build the system
/// refuses to authorize (unsigned), or a failed request, as ``NotificationAuthorizationState/unavailable``.
public actor UNNotificationAuthorization: NotificationAuthorizing {
    private let center: UNUserNotificationCenter
    private var requested = false

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func state() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            guard !requested else { return .unavailable }
            requested = true
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if !granted { NotificationsLog.event("denied") }
                return granted ? .authorized : .denied
            } catch {
                NotificationsLog.event("authorization request failed")
                return .unavailable
            }
        default:
            return .unavailable
        }
    }
}

/// Presents through the system when it is authorized and accepts the request. When the system
/// cannot decide or deliver (``NotificationAuthorizationState/unavailable``, or it refuses the
/// request) it uses an in-app banner, so mirrored notifications still show in a build the system
/// will not deliver for. When the user explicitly denied notifications nothing is shown; the
/// state is reported through `onState` so the UI can hint at System Settings.
public final class FallbackNotificationPresenter: NotificationPresenter, Sendable {
    private let system: any NotificationPresenter
    private let authorization: any NotificationAuthorizing
    private let banners: any NotificationBannerPresenting
    private let onState: @Sendable (NotificationAuthorizationState) async -> Void

    public init(
        system: any NotificationPresenter,
        authorization: any NotificationAuthorizing,
        banners: any NotificationBannerPresenting,
        onState: @escaping @Sendable (NotificationAuthorizationState) async -> Void = { _ in }
    ) {
        self.system = system
        self.authorization = authorization
        self.banners = banners
        self.onState = onState
    }

    public var responses: AsyncStream<NotificationResponseEvent> { system.responses }

    @discardableResult
    public func add(_ request: UNNotificationRequest) async -> Bool {
        let state = await authorization.state()
        await onState(state)
        if state == .denied {
            NotificationsLog.event("dropped, notifications denied")
            return false
        }
        if state == .authorized, await system.add(request) {
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
