import Synchronization
import TandemCrypto
import TandemProtocol
import TandemTransport

/// Runs one ``FocusSyncSender`` per registered session (E22-13). Each session gets its own
/// ``FocusStateSource``, because a source's `changes` stream is unicast. The sender is the only
/// reader this service starts on the session; it goes through ``TandemSession/receive(_:)``.
public final class FocusSessionService: SessionService, Sendable {
    private let makeSource: @Sendable () -> any FocusStateSource
    private let senders = Mutex<[SpkiFingerprint: FocusSyncSender]>([:])

    public init(makeSource: @escaping @Sendable () -> any FocusStateSource) {
        self.makeSource = makeSource
    }

    public func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let sender = FocusSyncSender(source: makeSource(), session: session)
        let replaced = senders.withLock { $0.updateValue(sender, forKey: peer) }
        await replaced?.stop()
        await sender.start()
    }

    public func detach(peer: SpkiFingerprint) async {
        let sender = senders.withLock { $0.removeValue(forKey: peer) }
        await sender?.stop()
    }
}
