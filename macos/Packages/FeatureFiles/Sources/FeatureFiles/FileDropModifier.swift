import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Routes file URLs dropped onto this view to `handler`.
    public func acceptsFileDrops(_ handler: SendEntryHandler) -> some View {
        onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in _ = await handler.handleDrop(urls: [url]) }
                }
            }
            return !providers.isEmpty
        }
    }
}
