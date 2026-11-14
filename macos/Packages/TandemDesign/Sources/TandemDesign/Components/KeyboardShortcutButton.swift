import SwiftUI

public extension View {
    /// Binds `shortcut` to `action` through an invisible zero-size button behind this view, for a
    /// second keyboard role (e.g. Return) on an action that already carries Escape through its
    /// own visible button. Hidden from accessibility so VoiceOver sees one control, not two.
    func keyboardShortcutButton(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) -> some View {
        background {
            Button("", action: action)
                .keyboardShortcut(shortcut)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
