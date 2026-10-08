import CryptoKit
import Foundation
import TandemProtocol
import TandemStore

/// Sender side of one outgoing file transfer (docs/protocol/SPEC.md #files-channel): a streaming
/// SHA-256 pass, `FileOffer`, then on `FileAccept` 256 KiB `FileChunk`s and `FileComplete`, fed
/// frame by frame to the ``FilesScheduler`` so credit gating and per-stream round-robin apply.
public actor FileSender: FilesFrameStream {
    public static let chunkSize = 262_144

    public enum State: Sendable, Equatable {
        case idle
        case offered
        case sending
        case completed
        case rejected(Tandem_V1_TransferReason)
        case cancelled(Tandem_V1_TransferReason)
        case failed
    }

    public private(set) var state: State = .idle

    public var isCancelled: Bool {
        if case .cancelled = state { true } else { false }
    }

    private let id: String
    private let name: String
    private let mime: String
    private let source: any FileChunkSource
    private let session: any TandemSession
    private let scheduler: FilesScheduler
    private let progress: (any TransferProgressReporting)?

    private var size: UInt64 = 0
    private var reader: (any FileChunkReader)?
    private var nextSeq: UInt64 = 0

    public init(
        id: String,
        name: String,
        mime: String,
        source: any FileChunkSource,
        session: any TandemSession,
        scheduler: FilesScheduler,
        progress: (any TransferProgressReporting)? = nil
    ) {
        self.id = id
        self.name = name
        self.mime = mime
        self.source = source
        self.session = session
        self.scheduler = scheduler
        self.progress = progress
    }

    /// Hashes the whole source in one streaming pass, then sends the `FileOffer`.
    public func start() async {
        guard state == .idle else { return }
        guard let digest = try? hashSource() else {
            FilesLog.event("send failed: source unreadable")
            state = .failed
            return
        }
        var offer = Tandem_V1_FileOffer()
        offer.id = id
        offer.name = name
        offer.size = size
        offer.mime = mime
        offer.sha256 = digest
        state = .offered
        FilesLog.event("offer sent")
        try? await session.send(.files, payload: .fileOffer(offer))
        await progress?.began(id: id, name: name, totalBytes: Int64(size), direction: .macToPhone) { [weak self] in
            await self?.cancel()
        }
    }

    public func handle(accept: Tandem_V1_FileAccept) async {
        guard accept.id == id, state == .offered else { return }
        FilesLog.event("accept received")
        state = .sending
        await scheduler.enqueue(stream: self)
    }

    /// Continues from the receiver's retained prefix on a fresh session: re-reads the source for its
    /// size, clamps the offset to a chunk boundary within the file and seeks there.
    public func handle(resume: Tandem_V1_FileResumeRequest) async {
        guard resume.id == id, [.idle, .offered, .sending].contains(state) else { return }
        if state == .idle {
            guard (try? hashSource()) != nil else {
                await cancelResume(.sourceUnavailable)
                return
            }
        }
        guard resume.fromOffset <= size, resume.fromOffset % UInt64(Self.chunkSize) == 0 else {
            await cancelResume(.protocolViolation)
            return
        }
        do {
            let opened = try source.makeReader()
            try opened.seek(to: resume.fromOffset)
            reader = opened
        } catch {
            await cancelResume(.sourceUnavailable)
            return
        }
        nextSeq = resume.fromOffset / UInt64(Self.chunkSize)
        state = .sending
        await scheduler.enqueue(stream: self)
    }

    public func handle(reject: Tandem_V1_FileReject) async {
        guard reject.id == id, state == .offered else { return }
        FilesLog.event("reject received", reason: reject.reason)
        state = .rejected(reject.reason)
        await progress?.ended(id: id, outcome: .failed(reason: String(describing: reject.reason)))
    }

    public func handle(cancel: Tandem_V1_FileCancel) async {
        guard cancel.id == id, state == .offered || state == .sending else { return }
        state = .cancelled(cancel.reason)
        reader = nil
        await progress?.ended(id: id, outcome: TransferOutcome(reason: cancel.reason))
    }

    /// User-initiated cancel: stops reading and queues `FileCancel{USER_CANCELLED}` behind any frame already in flight.
    public func cancel() async {
        guard state == .offered || state == .sending else { return }
        await scheduler.enqueue(response: cancelFrame(.userCancelled))
        await progress?.ended(id: id, outcome: .cancelled)
    }

    public func nextFrame() async -> Tandem_V1_Envelope.OneOf_Payload? {
        guard state == .sending else { return nil }
        let offset = nextSeq * UInt64(Self.chunkSize)
        if offset >= size {
            state = .completed
            var complete = Tandem_V1_FileComplete()
            complete.id = id
            await progress?.ended(id: id, outcome: .completed)
            return .fileComplete(complete)
        }
        guard let data = readChunk(at: offset) else {
            let frame = cancelFrame(.ioError)
            await progress?.ended(id: id, outcome: TransferOutcome(reason: .ioError))
            return frame
        }
        var chunk = Tandem_V1_FileChunk()
        chunk.id = id
        chunk.seq = nextSeq
        chunk.offset = offset
        chunk.data = data
        nextSeq += 1
        await progress?.delivered(id: id, bytes: Int64(offset) + Int64(data.count))
        return .fileChunk(chunk)
    }

    private func cancelResume(_ reason: Tandem_V1_TransferReason) async {
        let frame = cancelFrame(reason)
        try? await session.send(.files, payload: frame)
        await progress?.ended(id: id, outcome: TransferOutcome(reason: reason))
    }

    private func hashSource() throws -> Data {
        let reader = try source.makeReader()
        var hasher = SHA256()
        var total: UInt64 = 0
        while true {
            let block = try reader.read(upTo: Self.chunkSize)
            if block.isEmpty { break }
            hasher.update(data: block)
            total += UInt64(block.count)
        }
        size = total
        return Data(hasher.finalize())
    }

    private func readChunk(at offset: UInt64) -> Data? {
        do {
            let reader = try currentReader()
            let length = Int(min(UInt64(Self.chunkSize), size - offset))
            let data = try reader.read(upTo: length)
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    private func currentReader() throws -> any FileChunkReader {
        if let reader { return reader }
        let opened = try source.makeReader()
        reader = opened
        return opened
    }

    private func cancelFrame(_ reason: Tandem_V1_TransferReason) -> Tandem_V1_Envelope.OneOf_Payload {
        state = .cancelled(reason)
        reader = nil
        var cancel = Tandem_V1_FileCancel()
        cancel.id = id
        cancel.reason = reason
        return .fileCancel(cancel)
    }
}
