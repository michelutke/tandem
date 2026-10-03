import Foundation

/// Staging and destination roots of incoming transfers. Staging must be on the destination's volume
/// and outside it so an in-flight transfer never shows up in the destination.
public struct TransferDirectories: Sendable, Equatable {
    public let destination: URL
    public let staging: URL

    public init(destination: URL, staging: URL) {
        self.destination = destination
        self.staging = staging
    }

    /// `~/Downloads/Tandem` plus the item-replacement directory for that volume.
    public static func system(fileManager: FileManager = .default) throws -> TransferDirectories {
        let downloads = try fileManager.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let destination = downloads.appendingPathComponent("Tandem", isDirectory: true)
        let staging = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true
        )
        return TransferDirectories(destination: destination, staging: staging)
    }
}

/// Open staging file; writes are append-only.
public protocol FileSinkHandle {
    func write(_ data: Data) throws
    func close() throws
}

/// Seam over staging-file creation so tests can inject write failures such as ENOSPC.
public protocol FileSink: Sendable {
    func create(at url: URL) throws -> any FileSinkHandle
    /// Opens an existing staging file for appending after its retained prefix.
    func reopen(at url: URL) throws -> any FileSinkHandle
}

public struct FileHandleSink: FileSink {
    public init() {}

    public func create(at url: URL) throws -> any FileSinkHandle {
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileHandleSinkHandle(handle: try FileHandle(forWritingTo: url))
    }

    public func reopen(at url: URL) throws -> any FileSinkHandle {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return FileHandleSinkHandle(handle: handle)
    }
}

private final class FileHandleSinkHandle: FileSinkHandle {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func close() throws {
        try handle.close()
    }
}
