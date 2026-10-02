import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore
@preconcurrency import UserNotifications

/// Presents `NotificationPosted` frames via ``NotificationPresenter`` (``NotificationRequestBuilder``
/// does the mapping) and tracks each delivered notification's identifier against the peer that
/// posted it, so ``purgeAll(peer:)`` -- registered with `TandemStore/PeerDataPurgeRegistry`
/// (E14-13) by a composition root -- removes exactly that phone's delivered notifications on
/// unpair.
public actor NotificationPresentationCoordinator: PeerDataPurging {
    private let presenter: any NotificationPresenter
    private let iconCache: IconCache?
    private var identifiersByPeer: [SpkiFingerprint: Set<String>] = [:]

    /// `iconCache` (E30-06) is optional so a coordinator built with no icon cache still presents
    /// notifications, just with no icon attachment.
    public init(presenter: any NotificationPresenter, iconCache: IconCache? = nil) {
        self.presenter = presenter
        self.iconCache = iconCache
    }

    /// Builds and presents `posted`, then records its request identifier (``Tandem_V1_NotificationPosted/key``)
    /// against `peer` for later ``purgeAll(peer:)``.
    public func present(_ posted: Tandem_V1_NotificationPosted, from peer: SpkiFingerprint) async {
        let request = NotificationRequestBuilder.build(posted, iconAttachment: await iconAttachment(for: posted))
        await presenter.add(request)
        identifiersByPeer[peer, default: []].insert(request.identifier)
    }

    /// Resolves `posted`'s icon via ``IconCache`` (cached icon, or the generic placeholder) and
    /// wraps it as a `UNNotificationAttachment` (E30-06). `nil` when this coordinator has no
    /// ``IconCache`` at all, or when the attachment fails to construct -- either way
    /// ``present(_:from:)`` still presents the notification, just without an icon.
    private func iconAttachment(for posted: Tandem_V1_NotificationPosted) async -> UNNotificationAttachment? {
        guard let iconCache else { return nil }
        let url = await iconCache.iconURL(packageName: posted.packageName, versionCode: posted.appVersionCode)
        return try? UNNotificationAttachment(identifier: "icon-\(posted.key)", url: url)
    }

    /// ``PeerDataPurging`` conformance: removes every notification recorded as posted by `peer`.
    /// A no-op if `peer` posted nothing (or already had everything purged).
    public func purgeAll(peer: SpkiFingerprint) async throws {
        guard let identifiers = identifiersByPeer.removeValue(forKey: peer), !identifiers.isEmpty else {
            return
        }
        await presenter.removeDelivered(identifiers: Array(identifiers))
    }
}

/// Reads `session`'s NOTIFY channel until it finishes (peer disconnect or app teardown),
/// presenting every `NotificationPosted` frame it sees via `coordinator` and, when `iconCache` is
/// given, storing every `IconData` frame it sees there (E30-06 -- `IconData` shares the NOTIFY
/// channel with `NotificationPosted`, so it is routed here rather than through a second, separate
/// channel reader: two independent readers pulling from the same channel's single stream would
/// race each other for frames). When `actionHandler` is given, every `NotificationActionResult`
/// goes to it (E30-08). Every other NOTIFY payload is ignored here
/// (`NotificationDismiss` handling is E30-18). Mirrors
/// `TandemTransport`'s `startControlRevokeReader`: a free function so a composition root can spawn
/// one per registered session without this package depending on `TandemTransport`'s
/// session-registry types. Where exactly that spawn happens in the app's composition root is out
/// of this issue's scope.
///
/// WARNING for whoever does that wiring (E30-16 or similar): E14-27 found that cancelling a
/// `Task` consuming an `AsyncStream` (`for await frame in frames`, exactly this shape) can drop
/// an already-buffered frame -- `AsyncStream.next()` can return `nil` on a cancelled consumer even
/// when a value was already queued. If the composition root ever cancels this returned `Task` on
/// session teardown (the same way `ListenerFactory.wireSession` used to), a `NotificationPosted`
/// frame that arrived in the same tick as the session closing could be silently dropped. Prefer
/// letting this reader finish on its own (the `for await` loop ends once `frames` finishes) over
/// cancelling it, or apply the same self-terminating-proxy-task pattern
/// `startControlRevokeReader` now uses if cancellation from the caller side is unavoidable.
public func startNotificationPresentationReader(
    peer: SpkiFingerprint,
    session: any TandemSession,
    coordinator: NotificationPresentationCoordinator,
    iconCache: IconCache? = nil,
    actionHandler: NotificationActionHandler? = nil
) -> Task<Void, Never> {
    Task {
        let frames = await session.receive(.notify)
        for await frame in frames {
            switch frame.payload {
            case .notificationPosted(let posted):
                await coordinator.present(posted, from: peer)
            case .iconData(let icon):
                await iconCache?.store(icon, from: peer)
            case .notificationActionResult(let result):
                await actionHandler?.handle(result)
            default:
                continue
            }
        }
    }
}
