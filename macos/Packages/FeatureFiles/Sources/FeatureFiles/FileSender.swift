import CryptoKit
import Foundation
import TandemProtocol

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

    private let id: String
    private let name: String
    private let mime: String
    private let source: any FileChunkSource
    private let session: any TandemSession
    private let scheduler: FilesScheduler

    private var size: UInt64 = 0
    private var reader: (any FileChunkReader)?
    private var nextSeq: UInt64 = 0

    public init(
        id: String,
        name: String,
        mime: String,
        source: any FileChunkSource,
        session: any TandemSession,
        scheduler: FilesScheduler
    ) {
        self.id = id
        self.name = name
        self.mime = mime
        self.source = source
        self.session = session
        self.scheduler = scheduler
    }

    /// Hashes the whole source in one streaming pass, then sends the `FileOffer`.
    public func start() async {
        guard state == .idle else { return }
        guard let digest = try? hashSource() else {
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
        try? await session.send(.files, payload: .fileOffer(offer))
    }

    public func handle(accept: Tandem_V1_FileAccept) async {
        guard accept.id == id, state == .offered else { return }
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

    public func handle(reject: Tandem_V1_FileReject) {
        guard reject.id == id, state == .offered else { return }
        state = .rejected(reject.reason)
    }

    public func handle(cancel: Tandem_V1_FileCancel) {
        guard cancel.id == id, state == .offered || state == .sending else { return }
        state = .cancelled(cancel.reason)
        reader = nil
    }

    public func nextFrame() async -> Tandem_V1_Envelope.OneOf_Payload? {
        guard state == .sending else { return nil }
        let offset = nextSeq * UInt64(Self.chunkSize)
        if offset >= size {
            state = .completed
            var complete = Tandem_V1_FileComplete()
            complete.id = id
            return .fileComplete(complete)
        }
        guard let data = readChunk(at: offset) else { return cancelFrame(.ioError) }
        var chunk = Tandem_V1_FileChunk()
        chunk.id = id
        chunk.seq = nextSeq
        chunk.offset = offset
        chunk.data = data
        nextSeq += 1
        return .fileChunk(chunk)
    }

    private func cancelResume(_ reason: Tandem_V1_TransferReason) async {
        let frame = cancelFrame(reason)
        try? await session.send(.files, payload: frame)
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
