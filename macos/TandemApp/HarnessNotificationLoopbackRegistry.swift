#if DEBUG
import FeatureNotifications
import Foundation
import TandemCrypto
import TandemProtocol

/// DEBUG-only decorator (E30-14) around the harness listener's ``ControlSessionRegistry``,
/// mirroring ``HarnessRevokeAwareSessionRegistry``'s shape: only `-HarnessNotificationLoopback
/// YES`'s notification-latency loopback scaffolding lives here. Every ``register(_:session:)``
/// spawns ``startNotificationPresentationReader(peer:session:coordinator:)`` for the newly Ready
/// session against `coordinator`, so every `NotificationPosted` frame the E15-15 JVM harness
/// client sends on NOTIFY is presented via the DEBUG `HarnessLatencyNotificationPresenter` -- this
/// has no real-production equivalent (production wiring of `NotificationPresentationCoordinator`
/// into the app's listener is a separate, later issue), so it has nowhere else to live.
final class HarnessNotificationLoopbackRegistry: ControlSessionRegistering, Sendable {
    private let wrapped: any ControlSessionRegistering
    private let coordinator: NotificationPresentationCoordinator

    init(wrapping registry: any ControlSessionRegistering, coordinator: NotificationPresentationCoordinator) {
        self.wrapped = registry
        self.coordinator = coordinator
    }

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        await wrapped.register(spkiFingerprint, session: session)
        _ = startNotificationPresentationReader(peer: spkiFingerprint, session: session, coordinator: coordinator)
    }

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        await wrapped.removeIfCurrent(spkiFingerprint, session: session)
    }
}
#endif
