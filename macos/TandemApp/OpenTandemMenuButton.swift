import AppKit
import SwiftUI

/// The menu bar dropdown's "Open Tandem" item (E22-09): opens the main window (ui-spec §7.1) via
/// the `openWindow` environment action, mirroring ``SettingsMenuButton``'s own `openSettings`
/// pattern.
struct OpenTandemMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Tandem") {
            openWindow(id: "main")
            NSApp.activate()
        }
            .accessibilityIdentifier("openTandemMenuItem")
            .accessibilityLabel("Open Tandem")
    }
}
