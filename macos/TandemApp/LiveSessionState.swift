import FeatureMessaging
import Foundation
import Observation
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTransport

/// The stores the Messages and Calls sections read from, exposed from the same instances the
/// session services write to.
struct MessagingStores: Sendable {
    let smsStore: any SmsStore
    let contactsStore: any ContactsStore
}

/// The attached session as the main window sees it: nil between sessions, so every section
/// observes connect and disconnect through one object. ``generation`` changes on each attach so a
/// view can drop state built over the previous session.
@MainActor
@Observable
final class LiveSessionState {
    private(set) var peer: SpkiFingerprint?
    private(set) var session: (any TandemSession)?
    private(set) var smsSync: SmsSyncClient?
    private(set) var deviceStatus: DeviceStatusViewModel?
    private(set) var generation = 0

    nonisolated init() {}

    func attach(peer: SpkiFingerprint, session: any TandemSession, deviceStatus: DeviceStatusViewModel) {
        self.peer = peer
        self.session = session
        self.deviceStatus = deviceStatus
        generation += 1
    }

    func setSmsSync(_ client: SmsSyncClient?) {
        smsSync = client
    }

    func detach() {
        session = nil
        smsSync = nil
        deviceStatus = nil
    }
}

/// Publishes each attached session and its phone status to ``LiveSessionState``.
final class LiveSessionService: SessionService, @unchecked Sendable {
    private let state: LiveSessionState

    init(state: LiveSessionState) {
        self.state = state
    }

    func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let state = state
        await MainActor.run {
            state.attach(peer: peer, session: session, deviceStatus: DeviceStatusViewModel(session: session))
        }
    }

    func detach(peer: SpkiFingerprint) async {
        let state = state
        await MainActor.run { state.detach() }
    }
}

/// ``ConversationSyncSource`` and ``ThreadListSyncStatusSource`` over whichever ``SmsSyncClient``
/// is attached; offline, no SIMs are known and the cached threads count as complete.
struct LiveMessagingSync: ConversationSyncSource, ThreadListSyncStatusSource {
    let live: LiveSessionState

    func simOptions() async -> [SimOption] {
        guard let client = await smsSyncClient() else { return [] }
        return await client.simOptions()
    }

    func sendErrorCode(clientMessageId: String) async -> Tandem_V1_SendSmsErrorCode? {
        guard let client = await smsSyncClient() else { return nil }
        return await client.sendErrorCode(clientMessageId: clientMessageId)
    }

    func current() async -> ThreadListSyncStatus {
        guard let client = await smsSyncClient() else { return .complete }
        switch await client.syncStatus {
        case .syncing: return .syncing
        case .complete: return .complete
        case .permissionRequired: return .permissionRequired
        }
    }

    private func smsSyncClient() async -> SmsSyncClient? {
        await MainActor.run { live.smsSync }
    }
}
