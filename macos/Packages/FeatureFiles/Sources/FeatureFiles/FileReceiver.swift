import CryptoKit
import Foundation
import TandemProtocol

/// Receiver side of incoming file transfers (docs/protocol/SPEC.md #files-channel "Chunking"):
/// stages `<id>.part` outside the destination, validates every chunk against its own reassembly
/// state, hashes incrementally and on a matching SHA-256 renames the file into the destination
/// under its sanitized name, never overwriting an existing file. Failures delete the staging file.
public actor FileReceiver {
    public static let chunkSize = 262_144
    public static let partRetention: TimeInterval = 24 * 60 * 60

    private struct Transfer {
        let offer: Tandem_V1_FileOffer
        let filename: String
        let partURL: URL
        let handle: any FileSinkHandle
        var hasher = SHA256()
        var written: UInt64 = 0
    }

    private let session: any TandemSession
    private let directories: TransferDirectories
    private let sink: any FileSink
    private let fileManager: FileManager
    private let peer: String
    private let now: @Sendable () -> Date
    private let notifier: ReceivedFileNotifier?
    private var transfers: [String: Transfer] = [:]

    public init(
        session: any TandemSession,
        directories: TransferDirectories,
        sink: any FileSink,
        peer: String,
        now: @escaping @Sendable () -> Date,
        notifier: ReceivedFileNotifier? = nil,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.directories = directories
        self.sink = sink
        self.fileManager = fileManager
        self.peer = peer
        self.now = now
        self.notifier = notifier
    }

    /// Opens the staging file for an accepted offer; rejects INVALID_NAME or cancels IO_ERROR on failure.
    public func begin(offer: Tandem_V1_FileOffer) async {
        guard transfers[offer.id] == nil else { return }
        guard Self.isSafeId(offer.id),
              let filename = try? FilenameSanitizer.sanitize(offer.name, transferId: offer.id) else {
            await sendReject(offer.id, .invalidName)
            return
        }
        let partURL = directories.staging.appendingPathComponent("\(offer.id).part")
        do {
            let handle = try sink.create(at: partURL)
            try PartAttributes.write(peer: peer, offer: offer, to: partURL)
            transfers[offer.id] = Transfer(offer: offer, filename: filename, partURL: partURL, handle: handle)
        } catch {
            try? fileManager.removeItem(at: partURL)
            await sendCancel(offer.id, .ioError)
        }
    }

    /// Sweeps staging after a reconnect: deletes `.part` files idle for over 24 h and, for each
    /// retained one bound to this peer, truncates to a 256 KiB boundary, re-hashes the prefix and
    /// sends `FileResumeRequest`. Returns the ids a resume was requested for.
    @discardableResult
    public func resumeRetained() async -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directories.staging.path)) ?? []
        var resumed: [String] = []
        for name in names.sorted() where name.hasSuffix(".part") {
            let partURL = directories.staging.appendingPathComponent(name)
            if isExpired(partURL) {
                try? fileManager.removeItem(at: partURL)
            } else if let id = await resume(partURL: partURL) {
                resumed.append(id)
            }
        }
        return resumed
    }

    private func isExpired(_ partURL: URL) -> Bool {
        let attributes = try? fileManager.attributesOfItem(atPath: partURL.path)
        guard let modified = attributes?[.modificationDate] as? Date else { return true }
        return now().timeIntervalSince(modified) > Self.partRetention
    }

    private func resume(partURL: URL) async -> String? {
        guard let stored = PartAttributes.read(from: partURL),
              stored.peer == peer,
              Self.isSafeId(stored.offer.id),
              partURL.lastPathComponent == "\(stored.offer.id).part",
              transfers[stored.offer.id] == nil else { return nil }
        let offer = stored.offer
        do {
            let retained = try fileManager.attributesOfItem(atPath: partURL.path)[.size] as? UInt64 ?? 0
            let boundary = min(retained, offer.size) / UInt64(Self.chunkSize) * UInt64(Self.chunkSize)
            let hasher = try truncateAndHash(partURL, to: boundary)
            let handle = try sink.reopen(at: partURL)
            var transfer = Transfer(
                offer: offer, filename: try FilenameSanitizer.sanitize(offer.name, transferId: offer.id),
                partURL: partURL, handle: handle
            )
            transfer.hasher = hasher
            transfer.written = boundary
            transfers[offer.id] = transfer
            var request = Tandem_V1_FileResumeRequest()
            request.id = offer.id
            request.fromOffset = boundary
            try? await session.send(.files, payload: .fileResumeRequest(request))
            return offer.id
        } catch {
            try? fileManager.removeItem(at: partURL)
            return nil
        }
    }

    private func truncateAndHash(_ partURL: URL, to length: UInt64) throws -> SHA256 {
        let handle = try FileHandle(forUpdating: partURL)
        defer { try? handle.close() }
        try handle.truncate(atOffset: length)
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        while let block = try handle.read(upToCount: Self.chunkSize), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher
    }

    public func handle(chunk: Tandem_V1_FileChunk) async {
        guard var transfer = transfers[chunk.id] else { return }
        let length = UInt64(chunk.data.count)
        guard chunk.data.count <= Self.chunkSize,
              chunk.offset == transfer.written,
              chunk.offset == chunk.seq &* UInt64(Self.chunkSize),
              chunk.offset + length <= transfer.offer.size else {
            await abort(chunk.id, .protocolViolation)
            return
        }
        do {
            try transfer.handle.write(chunk.data)
        } catch {
            await abort(chunk.id, Self.isOutOfSpace(error) ? .insufficientSpace : .ioError)
            return
        }
        transfer.hasher.update(data: chunk.data)
        transfer.written += length
        transfers[chunk.id] = transfer
    }

    public func handle(complete: Tandem_V1_FileComplete) async {
        guard let transfer = transfers[complete.id] else { return }
        guard transfer.written == transfer.offer.size else {
            await abort(complete.id, .protocolViolation)
            return
        }
        let digest = Data(transfer.hasher.finalize())
        guard constantTimeEqual(digest, transfer.offer.sha256) else {
            await abort(complete.id, .hashMismatch)
            return
        }
        do {
            try transfer.handle.close()
            let saved = try moveIntoDestination(transfer)
            transfers[complete.id] = nil
            await notifier?.notifyReceived(destination: saved)
        } catch {
            await abort(complete.id, .ioError)
        }
    }

    public func handle(cancel: Tandem_V1_FileCancel) {
        guard let transfer = transfers.removeValue(forKey: cancel.id) else { return }
        discard(transfer)
    }

    /// User-initiated cancel: deletes the `.part` file, publishes nothing and sends `FileCancel{USER_CANCELLED}`.
    public func cancel(id: String) async {
        guard transfers[id] != nil else { return }
        await abort(id, .userCancelled)
    }

    private func abort(_ id: String, _ reason: Tandem_V1_TransferReason) async {
        if let transfer = transfers.removeValue(forKey: id) {
            discard(transfer)
        }
        await sendCancel(id, reason)
    }

    private func discard(_ transfer: Transfer) {
        try? transfer.handle.close()
        try? fileManager.removeItem(at: transfer.partURL)
    }

    private func moveIntoDestination(_ transfer: Transfer) throws -> URL {
        try fileManager.createDirectory(at: directories.destination, withIntermediateDirectories: true)
        var attempt = 0
        while true {
            let target = directories.destination.appendingPathComponent(
                Self.collisionName(transfer.filename, attempt: attempt)
            )
            do {
                try fileManager.moveItem(at: transfer.partURL, to: target)
                return target
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                attempt += 1
            }
        }
    }

    private func sendCancel(_ id: String, _ reason: Tandem_V1_TransferReason) async {
        var message = Tandem_V1_FileCancel()
        message.id = id
        message.reason = reason
        try? await session.send(.files, payload: .fileCancel(message))
    }

    private func sendReject(_ id: String, _ reason: Tandem_V1_TransferReason) async {
        var message = Tandem_V1_FileReject()
        message.id = id
        message.reason = reason
        try? await session.send(.files, payload: .fileReject(message))
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func isSafeId(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 64 && id.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
                || $0 == 0x2D || $0 == 0x5F
        }
    }

    private static func collisionName(_ filename: String, attempt: Int) -> String {
        guard attempt > 0 else { return filename }
        let name = filename as NSString
        let pathExtension = name.pathExtension
        let stem = name.deletingPathExtension
        let suffixed = "\(stem) (\(attempt))"
        return pathExtension.isEmpty ? suffixed : "\(suffixed).\(pathExtension)"
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))
            || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
    }
}
