import Foundation
import TandemProtocol

/// Seam over `UNUserNotificationCenter` for the received-file notification. The notification
/// carries only the sanitized file name, never file contents.
public protocol ReceivedFilePresenter: Sendable {
    func present(displayName: String, destination: URL) async
    var activations: AsyncStream<URL> { get }
}

/// Seam over `NSWorkspace.activateFileViewerSelecting`.
public protocol FileRevealer: Sendable {
    func reveal(_ url: URL) async
}

/// Presents one notification per successfully received file and reveals the file when it is activated.
public struct ReceivedFileNotifier: Sendable {
    private let presenter: any ReceivedFilePresenter
    private let revealer: any FileRevealer

    public init(presenter: any ReceivedFilePresenter, revealer: any FileRevealer) {
        self.presenter = presenter
        self.revealer = revealer
    }

    public func notifyReceived(destination: URL) async {
        let displayName = DisplayStringSanitizer.sanitize(
            Data(destination.lastPathComponent.utf8), kind: .name
        )
        await presenter.present(displayName: displayName, destination: destination)
    }

    /// Reveals each activated notification's file until the activation stream ends.
    public func runActivations() async {
        for await destination in presenter.activations {
            await revealer.reveal(destination)
        }
    }
}
