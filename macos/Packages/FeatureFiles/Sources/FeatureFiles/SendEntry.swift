import Foundation

/// Seam over the transfer service that owns outgoing ``FileSender``s: starts one `FileOffer` per file.
public protocol FileTransferService: Sendable {
    var isConnected: Bool { get }
    func startOffer(for url: URL) async
}

/// Feature-local seam over the Send File open panel.
public protocol FilePicker: Sendable {
    /// The chosen file URLs; empty when the user cancels.
    @MainActor func pickFiles() async -> [URL]
}

public enum SendEntryResult: Sendable, Equatable {
    case started(count: Int)
    case unsupportedFolder
    case notConnected
    case cancelled
}

/// Entry points that start file offers: files dropped onto the menu bar window and the menu bar
/// "Send File…" quick action (PRD F-7.2, F-4.2).
@MainActor
public final class SendEntryHandler {
    private let picker: any FilePicker
    private let transfer: (any FileTransferService)?

    /// - Parameter transfer: `nil` while no peer is paired; every entry point then yields `notConnected`.
    public init(picker: any FilePicker, transfer: (any FileTransferService)?) {
        self.picker = picker
        self.transfer = transfer
    }

    public func handleDrop(urls: [URL]) async -> SendEntryResult {
        guard let transfer, transfer.isConnected else { return .notConnected }
        let files = urls.filter { !Self.isDirectory($0) }
        guard !files.isEmpty else { return .unsupportedFolder }
        for file in files {
            await transfer.startOffer(for: file)
        }
        return .started(count: files.count)
    }

    public func sendFileQuickAction() async -> SendEntryResult {
        guard let transfer, transfer.isConnected else { return .notConnected }
        let chosen = await picker.pickFiles()
        guard !chosen.isEmpty else { return .cancelled }
        return await handleDrop(urls: chosen)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
