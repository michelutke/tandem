import AppKit

/// Production ``FilePicker`` over `NSOpenPanel`.
public struct OpenPanelFilePicker: FilePicker {
    public init() {}

    @MainActor
    public func pickFiles() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }
}
