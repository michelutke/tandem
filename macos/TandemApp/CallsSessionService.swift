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
        viewModel = await MainActor.run {
            let viewModel = CallAlertViewModel(
                presenter: alertPresenter,
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
    }

    func detach(peer: SpkiFingerprint) async {
        await routing.router.setSink(nil, for: Self.routerKey)
        alertPresenter?.finish()
        alertPresenter = nil
        viewModel = nil
        let activeCall = activeCall
        await MainActor.run { activeCall.set(nil) }
    }
}
