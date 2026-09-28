import AppKit
import Foundation

/// Opens a URL in the default handler (System Settings deep links, in particular). Seam over
/// `NSWorkspace` (mirrors ``LoginItemService``'s seam over `SMAppService`): ``WorkspaceURLOpener``
/// is the real implementation; tests drive a recording fake instead.
protocol URLOpener {
    func open(_ url: URL)
}

/// The production ``URLOpener``, over `NSWorkspace.shared`.
final class WorkspaceURLOpener: URLOpener {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
