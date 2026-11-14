import Foundation
import FeatureCalls
import FeatureNotifications
import Observation
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTransport

/// Fans the single presenter-responses reader's events out to the services of whichever session is
/// attached (accept prompts, call alerts): `UNNotificationPresenter.responses` is single-consumer.
actor NotificationResponseRouter {
    typealias Sink = @Sendable (NotificationResponseEvent) -> Void

    private var sinks: [String: Sink] = [:]

    func setSink(_ sink: Sink?, for key: String) {
        sinks[key] = sink
    }

    func route(_ event: NotificationResponseEvent) {
        for sink in sinks.values {
            sink(event)
        }
    }
}

/// What the notification-backed prompts of a session need from ``NotificationsSessionService``.
struct NotificationRouting: Sendable {
    let presenter: any NotificationPresenter
    let categories: CategoryRegistry
    let router: NotificationResponseRouter
}

/// The attached session's ``CallAlertViewModel``, if any, so the menu bar's Hang Up item observes
/// one stable object across reconnects.
@MainActor
@Observable
final class ActiveCallAlert {
    private(set) var viewModel: CallAlertViewModel?

    nonisolated init() {}

    func set(_ viewModel: CallAlertViewModel?) {
        self.viewModel = viewModel
    }
}

/// Incoming-call alerts and Hang Up for the attached session: a ``CallAlertViewModel`` observing
/// CALLS through ``TandemSession/receive(_:)``, presenting through the shared notification presenter.
final class CallsSessionService: SessionService, @unchecked Sendable {
    private static let routerKey = "calls"

    private let contacts: any ContactsStore
    private let routing: NotificationRouting
    private let activeCall: ActiveCallAlert
    private var viewModel: CallAlertViewModel?
    private var alertPresenter: NotificationCallAlertPresenter?
    private var inAppAlerts: AlertCallPresenter?

    init(contacts: any ContactsStore, routing: NotificationRouting, activeCall: ActiveCallAlert) {
        self.contacts = contacts
        self.routing = routing
        self.activeCall = activeCall
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let alertPresenter = NotificationCallAlertPresenter(
            presenter: routing.presenter,
            categories: routing.categories
        )
        await routing.router.setSink({ alertPresenter.handle($0) }, for: Self.routerKey)
        let contacts = contacts
        let activeCall = activeCall
        let inAppAlerts = await MainActor.run { AlertCallPresenter() }
        viewModel = await MainActor.run {
            let viewModel = CallAlertViewModel(
                presenter: alertPresenter,
                fallbackPresenter: inAppAlerts,
                session: session,
                contacts: contacts,
                peer: peer,
                now: { Date() }
            )
            viewModel.start()
            activeCall.set(viewModel)
            return viewModel
        }
        self.alertPresenter = alertPresenter
        self.inAppAlerts = inAppAlerts
    }

    func detach(peer: SpkiFingerprint) async {
        await routing.router.setSink(nil, for: Self.routerKey)
        await alertPresenter?.removeAll()
        alertPresenter?.finish()
        alertPresenter = nil
        if let inAppAlerts { await MainActor.run { inAppAlerts.finish() } }
        inAppAlerts = nil
        viewModel = nil
        let activeCall = activeCall
        await MainActor.run { activeCall.set(nil) }
    }
}

/// Notification presentation, icon storage, dismiss sync and action replies for the attached
/// session. `UNNotificationPresenter.responses` is single-consumer, so one long-lived reader
/// routes every response to the handlers of whichever session is currently attached and, through
/// ``routing``, to the accept-prompt and call-alert presenters.
final class NotificationsSessionService: SessionService, @unchecked Sendable {
    private actor ActiveHandlers {
        private var handlers: (action: NotificationActionHandler, dismiss: NotificationDismissSync)?

        func set(_ handlers: (action: NotificationActionHandler, dismiss: NotificationDismissSync)?) {
            self.handlers = handlers
        }

        func route(_ event: NotificationResponseEvent) async {
            await handlers?.action.handle(event)
            await handlers?.dismiss.handle(event)
        }
    }

    static let hidesContentWhenLockedKey = "hideNotificationContentWhenLocked"

    private let presenter: any NotificationPresenter
    let coordinator: NotificationPresentationCoordinator
    let routing: NotificationRouting
    private let iconCache: IconCache?
    private let active = ActiveHandlers()
    private let screenLock = DistributedScreenLockState(notificationCenter: DistributedNotificationCenter.default())

    init(iconCache: IconCache?) {
        let authorization = UNNotificationAuthorization()
        let banners = MainActor.assumeIsolated { NotificationBannerPanelController() }
        let presenter = FallbackNotificationPresenter(
            system: UNNotificationPresenter(),
            authorization: authorization,
            banners: banners,
            onState: NotificationPermissionViewModel.report
        )
        self.presenter = presenter
        Task { await NotificationPermissionViewModel.report(await authorization.state()) }
        self.iconCache = iconCache
        coordinator = NotificationPresentationCoordinator(
            presenter: presenter,
            iconCache: iconCache,
            screenLockState: screenLock,
            hidesContentWhenLocked: {
                let key = NotificationsSessionService.hidesContentWhenLockedKey
                return UserDefaults.standard.object(forKey: key) as? Bool ?? true
            }
        )
        let router = NotificationResponseRouter()
        routing = NotificationRouting(
            presenter: presenter,
            categories: CategoryRegistry(presenter: presenter),
            router: router
        )
        let active = active
        Task {
            for await event in presenter.responses {
                await active.route(event)
                await router.route(event)
            }
        }
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let action = NotificationActionHandler(presenter: presenter, session: session)
        let dismiss = NotificationDismissSync(presenter: presenter, session: session)
        await active.set((action, dismiss))
        _ = startNotificationPresentationReader(
            peer: peer,
            session: session,
            coordinator: coordinator,
            iconCache: iconCache,
            actionHandler: action,
            dismissSync: dismiss
        )
    }

    func detach(peer: SpkiFingerprint) async {
        await active.set(nil)
    }
}
