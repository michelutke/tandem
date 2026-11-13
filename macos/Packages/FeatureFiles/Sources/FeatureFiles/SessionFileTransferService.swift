import Foundation
import UniformTypeIdentifiers
import TandemProtocol
import TandemStore

/// The production ``FileTransferService`` for one session: every ``startOffer(for:)`` builds a
/// ``FileSender`` over the shared ``FilesScheduler`` and keeps it until the peer rejects or cancels
/// it, so the FILES reader (``FilesChannelRouter``) can route `FileAccept`, `FileReject`,
/// `FileCancel` and `FileResumeRequest` back to it.
public final class SessionFileTransferService: FileTransferService {
    public let isConnected = true

    private let session: any TandemSession
    private let scheduler: FilesScheduler
    private let resumeResponder: FileResumeResponder
    private let senders = SenderRegistry()
    private let progress: (any TransferProgressReporting)?
    private let makeTransferId: @Sendable () -> String

    public init(
        session: any TandemSession,
        scheduler: FilesScheduler,
        progress: (any TransferProgressReporting)? = nil,
        makeTransferId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.session = session
        self.scheduler = scheduler
        resumeResponder = FileResumeResponder(session: session)
        self.progress = progress
        self.makeTransferId = makeTransferId
    }

    public func startOffer(for url: URL) async {
        await startOffer(for: url, onEnded: {})
    }

    public func startOffer(for url: URL, onEnded: @escaping @Sendable () -> Void) async {
        let id = makeTransferId()
        let reporter = EndNotifyingProgress(base: progress) { [weak self] in
            onEnded()
            Task { await self?.forget(id: id) }
        }
        let sender = FileSender(
            id: id,
            name: url.lastPathComponent,
            mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
            source: LocalFileChunkSource(url: url),
            session: session,
            scheduler: scheduler,
            progress: reporter
        )
        await senders.register(id: id, sender: sender)
        await resumeResponder.register(id: id, sender: sender)
        await sender.start()
        if await sender.state == .failed {
            onEnded()
            await forget(id: id)
        }
    }

    /// Ends every transfer still in flight as failed; called once the session's FILES stream has finished.
    func sessionEnded() async {
        for sender in await senders.removeAll() {
            await sender.disconnected()
        }
    }

    private func forget(id: String) async {
        _ = await senders.remove(id: id)
        await resumeResponder.remove(id: id)
    }

    func handle(accept: Tandem_V1_FileAccept) async {
        await senders.sender(id: accept.id)?.handle(accept: accept)
    }

    func handle(reject: Tandem_V1_FileReject) async {
        await senders.remove(id: reject.id)?.handle(reject: reject)
    }

    func handle(cancel: Tandem_V1_FileCancel) async {
        await senders.remove(id: cancel.id)?.handle(cancel: cancel)
    }

    func handle(resume: Tandem_V1_FileResumeRequest) async {
        await resumeResponder.handle(resume: resume)
    }
}

private actor SenderRegistry {
    private var senders: [String: FileSender] = [:]

    func register(id: String, sender: FileSender) {
        senders[id] = sender
    }

    func sender(id: String) -> FileSender? {
        senders[id]
    }

    func remove(id: String) -> FileSender? {
        senders.removeValue(forKey: id)
    }

    func removeAll() -> [FileSender] {
        defer { senders = [:] }
        return Array(senders.values)
    }
}

private struct EndNotifyingProgress: TransferProgressReporting {
    let base: (any TransferProgressReporting)?
    let onEnded: @Sendable () -> Void

    func began(
        id: String,
        name: String,
        totalBytes: Int64,
        direction: TransferDirection,
        cancel: @escaping @Sendable () async -> Void
    ) async {
        await base?.began(id: id, name: name, totalBytes: totalBytes, direction: direction, cancel: cancel)
    }

    func delivered(id: String, bytes: Int64) async {
        await base?.delivered(id: id, bytes: bytes)
    }

    func ended(id: String, outcome: TransferOutcome, savedFile: URL?) async {
        await base?.ended(id: id, outcome: outcome, savedFile: savedFile)
        onEnded()
    }
}

/// Routes the active session's ``FileTransferService`` calls to whichever session is currently
/// attached (``attach(_:)`` / ``detach()``), so the one long-lived ``SendEntryHandler`` and
/// ``SendRequestAgent`` keep working across reconnects. ``isConnected`` is false between sessions.
public final class ActiveFileTransferService: FileTransferService, @unchecked Sendable {
    private let lock = NSLock()
    private var current: (any FileTransferService)?

    public init() {}

    public var isConnected: Bool {
        lock.withLock { current }?.isConnected ?? false
    }

    public func attach(_ service: any FileTransferService) {
        lock.withLock { current = service }
    }

    public func detach() {
        lock.withLock { current = nil }
    }

    public func startOffer(for url: URL) async {
        let service = lock.withLock { current }
        await service?.startOffer(for: url)
    }

    public func startOffer(for url: URL, onEnded: @escaping @Sendable () -> Void) async {
        let service = lock.withLock { current }
        await service?.startOffer(for: url, onEnded: onEnded)
    }
}
