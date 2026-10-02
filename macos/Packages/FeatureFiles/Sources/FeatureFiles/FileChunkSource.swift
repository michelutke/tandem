import Foundation

/// Sequential reader over the bytes of one file being sent.
public protocol FileChunkReader: Sendable {
    /// Returns up to `count` bytes; an empty result means end of file.
    func read(upTo count: Int) throws -> Data
}

/// Opens fresh ``FileChunkReader``s over one source file (once for the hash pass, once for sending).
public protocol FileChunkSource: Sendable {
    func makeReader() throws -> any FileChunkReader
}

/// Production ``FileChunkSource`` over a local file URL.
public struct LocalFileChunkSource: FileChunkSource {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeReader() throws -> any FileChunkReader {
        FileHandleChunkReader(handle: try FileHandle(forReadingFrom: url))
    }
}

private final class FileHandleChunkReader: FileChunkReader, @unchecked Sendable {
    // Driven by one FileSender actor at a time; never shared across tasks concurrently.
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    deinit {
        try? handle.close()
    }

    func read(upTo count: Int) throws -> Data {
        try handle.read(upToCount: count) ?? Data()
    }
}
