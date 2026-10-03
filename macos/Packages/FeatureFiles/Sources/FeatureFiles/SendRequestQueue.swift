import Foundation

public enum SendRequestQueueError: Error, Equatable {
    case invalidFileCount(Int)
    case appGroupUnavailable
}

/// App Group file queue between the Share extension and the agent (PRD F-7.2). The extension only
/// writes; the agent treats every entry as untrusted input. Layout: `<root>/<requestId>/<index>/<name>`.
public struct SendRequestQueue: Sendable {
    public static let appGroupIdentifier = "group.dev.tandem"
    public static let maxFilesPerRequest = 20
    public static let maxFileSize: UInt64 = 1 << 36

    private static let directoryName = "SendQueue"

    public let directory: URL

    public init(groupRoot: URL) {
        directory = groupRoot.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    public init(appGroupIdentifier: String = Self.appGroupIdentifier) throws {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw SendRequestQueueError.appGroupUnavailable }
        self.init(groupRoot: root)
    }

    /// Copies each file into the queue as one request; the order of `files` is preserved.
    @discardableResult
    public func enqueue(files: [URL]) throws -> URL {
        guard (1...Self.maxFilesPerRequest).contains(files.count) else {
            throw SendRequestQueueError.invalidFileCount(files.count)
        }
        let fileManager = FileManager.default
        let request = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            for (index, file) in files.enumerated() {
                let slot = request.appendingPathComponent(Self.slotName(index), isDirectory: true)
                try fileManager.createDirectory(at: slot, withIntermediateDirectories: true)
                try fileManager.copyItem(at: file, to: slot.appendingPathComponent(file.lastPathComponent))
            }
        } catch {
            try? fileManager.removeItem(at: request)
            throw error
        }
        return request
    }

    /// Validated copies of every pending request, oldest first. Entries failing validation are
    /// deleted and skipped; a request with more than 20 slots is deleted whole.
    public func dequeue() -> [[URL]] {
        let fileManager = FileManager.default
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let requests = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return requests
            .sorted { Self.creationDate($0) < Self.creationDate($1) }
            .compactMap { validatedFiles(inRequest: $0, root: root) }
            .filter { !$0.isEmpty }
    }

    /// Removes the queued copy (and its emptied slot and request directories) once its transfer ended.
    public func discard(copy: URL) {
        let fileManager = FileManager.default
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isInside(copy.deletingLastPathComponent(), root: root) else { return }
        try? fileManager.removeItem(at: copy)
        let slot = copy.deletingLastPathComponent()
        try? fileManager.removeItem(at: slot)
        let request = slot.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: request.path))?.isEmpty == true {
            try? fileManager.removeItem(at: request)
        }
    }

    private func validatedFiles(inRequest request: URL, root: URL) -> [URL]? {
        let fileManager = FileManager.default
        guard Self.isPlainDirectory(request), Self.isInside(request, root: root) else {
            try? fileManager.removeItem(at: request)
            return nil
        }
        let slots = ((try? fileManager.contentsOfDirectory(at: request, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard slots.count <= Self.maxFilesPerRequest else {
            try? fileManager.removeItem(at: request)
            return nil
        }
        return slots.compactMap { validatedFile(inSlot: $0, root: root) }
    }

    private func validatedFile(inSlot slot: URL, root: URL) -> URL? {
        let fileManager = FileManager.default
        guard Self.isPlainDirectory(slot),
              let entries = try? fileManager.contentsOfDirectory(at: slot, includingPropertiesForKeys: nil),
              entries.count == 1,
              let file = entries.first,
              Self.isAcceptableFile(file, root: root)
        else {
            try? fileManager.removeItem(at: slot)
            return nil
        }
        return file
    }

    private static func isAcceptableFile(_ file: URL, root: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]),
              values.isSymbolicLink != true,
              values.isRegularFile == true,
              UInt64(values.fileSize ?? 0) <= maxFileSize
        else { return false }
        return isInside(file, root: root)
    }

    private static func isPlainDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else {
            return false
        }
        return values.isSymbolicLink != true && values.isDirectory == true
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let rootComponents = root.pathComponents
        return resolved.count > rootComponents.count && Array(resolved.prefix(rootComponents.count)) == rootComponents
    }

    private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }

    private static func slotName(_ index: Int) -> String {
        String(format: "%02d", index)
    }
}
