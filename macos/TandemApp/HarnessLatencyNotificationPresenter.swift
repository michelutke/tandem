#if DEBUG
import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// DEBUG-only `NotificationPresenter` for the E30-14 loopback latency harness
/// (`-HarnessNotificationLoopback YES`): never touches `UNUserNotificationCenter` (this process
/// runs unattended, with no notification-authorization prompt possible), and logs only a
/// sequence number and a timestamp per `add(_:)` call -- never the request's title/body (invariant
/// 7, CLAUDE.md: no notification content in logs). `request.identifier` is safe to log because
/// `NotificationRequestBuilder` sets it to the `NotificationPosted.key` field, and this harness's
/// own JVM client (`tools/harness/integration/e30-14.sh`, `HarnessCli.sendNotifications`) sets
/// that key to a plain decimal sequence number, never real content.
actor HarnessLatencyNotificationPresenter: @preconcurrency NotificationPresenter {
    nonisolated let responses: AsyncStream<NotificationResponseEvent>
    private let responsesContinuation: AsyncStream<NotificationResponseEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<NotificationResponseEvent>.makeStream(bufferingPolicy: .unbounded)
        responses = stream
        responsesContinuation = continuation
    }

    /// Logs `harness-notification-latency: <sequence> <epochMillis>` -- the driver script
    /// correlates `<sequence>` against the JVM client's own `EVENT SENT <sequence> <epochMillis>`
    /// line to compute this frame's receive-to-presenter latency.
    @discardableResult
    func add(_ request: UNNotificationRequest) async -> Bool {
        let epochMillis = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        print("harness-notification-latency: \(request.identifier) \(epochMillis)")
        fflush(stdout)
        return true
    }

    func removeDelivered(identifiers: [String]) async {}

    func setCategories(_ categories: Set<UNNotificationCategory>) async {}
}
#endif
