import Observation
import TandemProtocol

/// The menu bar's four quick actions (backlog E22-02, PRD F-4.2, UC-05): Send File (E40-10),
/// Push Clipboard (E31-11), Find Phone (E23-07), and Mirror (E61-12) -- each of those features
/// lands in its own later issue, so this view model only owns the four exact labels, the
/// disabled-when-disconnected rule, and dispatch to an injected handler closure per action, the
/// same seam ``LaunchAtLoginViewModel`` already uses so tests can pass recording fakes without a
/// protocol/service type.
///
/// Presentation-independent -- no `SwiftUI` import -- unit tested against four recording
/// closures, matching ``LaunchAtLoginViewModel``'s own injected-dependency convention.
/// ``QuickActionsView`` is its SwiftUI presentation.
@MainActor
@Observable
final class QuickActionsViewModel {
    /// One of the four quick actions this issue's acceptance enumerates, in the spec's own order
    /// (Send File, Push Clipboard, Find Phone, Mirror).
    enum Action: Sendable, Equatable, CaseIterable {
        case sendFile
        case pushClipboard
        case findPhone
        case mirror

        /// The exact label text (backlog E22-02 "UI strings (exact)").
        var label: String {
            switch self {
            case .sendFile: return "Send File…"
            case .pushClipboard: return "Push Clipboard"
            case .findPhone: return "Find Phone"
            case .mirror: return "Mirror Phone"
            }
        }
    }

    /// `true` while a peer is connected -- every action is disabled otherwise (acceptance: "Each
    /// item is disabled when no device is connected"). This issue does not need this to react to
    /// a real session's state stream -- no such stream is composed into `MenuContentView` yet,
    /// the same gap `MenuBarViewModel(stateStream: nil, peerName: nil)` already documents -- a
    /// later issue wires this to the paired session's own connection state.
    var isConnected: Bool

    @ObservationIgnored
    private nonisolated(unsafe) var connectionTask: Task<Void, Never>?

    private let sendFile: () -> Void
    private let pushClipboard: () -> Void
    private let findPhone: () -> Void
    private let mirror: () -> Void

    init(
        isConnected: Bool,
        sendFile: @escaping () -> Void,
        pushClipboard: @escaping () -> Void,
        findPhone: @escaping () -> Void,
        mirror: @escaping () -> Void
    ) {
        self.isConnected = isConnected
        self.sendFile = sendFile
        self.pushClipboard = pushClipboard
        self.findPhone = findPhone
        self.mirror = mirror
    }

    deinit {
        connectionTask?.cancel()
    }

    /// Keeps ``isConnected`` equal to whether the paired session is `.ready`, from the session
    /// host's own connection-state stream; `nil` (nothing paired) leaves it unchanged.
    func observeConnection(_ states: AsyncStream<ConnectionStateMachine.ConnectionState>?) {
        connectionTask?.cancel()
        guard let states else { return }
        connectionTask = Task { [weak self] in
            for await state in states {
                self?.isConnected = state == .ready
            }
        }
    }

    /// Invokes `action`'s own injected handler exactly once, or does nothing while
    /// ``isConnected`` is `false` (guard pattern, matching
    /// ``LaunchAtLoginViewModel/setEnabled(_:)``'s style) -- covers both "disabled when
    /// disconnected" and "invokes its handler exactly once".
    func select(_ action: Action) {
        guard isConnected else { return }
        switch action {
        case .sendFile: sendFile()
        case .pushClipboard: pushClipboard()
        case .findPhone: findPhone()
        case .mirror: mirror()
        }
    }
}
