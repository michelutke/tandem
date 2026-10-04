import Foundation
import UniformTypeIdentifiers
import TandemProtocol

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
        let id = makeTransferId()
        let sender = FileSender(
            id: id,
            name: url.lastPathComponent,
            mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
            source: LocalFileChunkSource(url: url),
            session: session,
            scheduler: scheduler,
            progress: progress
        )
        await senders.register(id: id, sender: sender)
        await resumeResponder.register(id: id, sender: sender)
        await sender.start()
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
}
