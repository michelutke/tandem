import Synchronization
import TandemCrypto
import TandemProtocol
import TandemTransport

/// Runs one clipboard sync per registered session: a ``ClipboardSender`` (poller plus the menu bar's
/// Push Clipboard) and a ``PasteboardWriter`` sharing one ``ClipboardLoopGuard``. Each reads the
/// CLIPBOARD channel only through ``TandemSession/receive(_:)``.
public final class ClipboardSessionService: SessionService, Sendable {
    private struct Attachment {
        let sender: ClipboardSender
        let writer: PasteboardWriter
    }

    private let source: any PasteboardSource
    private let clock: any Clock<Duration>
    private let active: ActiveClipboard
    private let attachments = Mutex<[SpkiFingerprint: Attachment]>([:])

    public init(source: any PasteboardSource, clock: any Clock<Duration>, active: ActiveClipboard) {
        self.source = source
        self.clock = clock
        self.active = active
    }

    public func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let loopGuard = ClipboardLoopGuard()
        let sender = ClipboardSender(source: source, clock: clock, session: session, loopGuard: loopGuard)
        let active = active
        let writer = PasteboardWriter(
            source: source,
            session: session,
            loopGuard: loopGuard,
            onApplied: { active.reportReceived() }
        )
        let replaced = attachments.withLock { $0.updateValue(Attachment(sender: sender, writer: writer), forKey: peer) }
        await stop(replaced)
        await writer.start()
        await sender.start()
        active.attach(sender)
    }

    public func detach(peer: SpkiFingerprint) async {
        let removed = attachments.withLock { $0.removeValue(forKey: peer) }
        active.detach()
        await stop(removed)
    }

    private func stop(_ attachment: Attachment?) async {
        guard let attachment else { return }
        await attachment.writer.stop()
        await attachment.sender.stop()
    }
}
