import AppKit

/// Handles the Finder Services "Send to phone" item (PRD F-7.2): starts one `FileOffer` per file URL
/// on the service pasteboard via ``SendEntryHandler``. Register as `NSApplication.servicesProvider`.
@MainActor
public final class FinderServicesProvider: NSObject {
    public static let noFilesError = "No files to send."
    public static let notConnectedError = "Connect your phone to send files."
    public static let unsupportedFolderError = "Folders can't be sent yet."

    private let handler: SendEntryHandler

    public init(handler: SendEntryHandler) {
        self.handler = handler
    }

    /// Selector named by `NSMessage` in the app Info.plist `NSServices` entry.
    @objc public func sendToPhone(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard Self.fileURLs(on: pasteboard).isEmpty == false else {
            error.pointee = Self.noFilesError as NSString
            return
        }
        Task { _ = await send(pasteboard: pasteboard) }
    }

    /// Returns an error string when no offer was started.
    public func send(pasteboard: NSPasteboard) async -> String? {
        let urls = Self.fileURLs(on: pasteboard)
        guard !urls.isEmpty else { return Self.noFilesError }
        switch await handler.handleDrop(urls: urls) {
        case .started: return nil
        case .notConnected: return Self.notConnectedError
        case .unsupportedFolder: return Self.unsupportedFolderError
        case .cancelled: return nil
        }
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }
}
