import Testing

@testable import TandemApp

/// E22-02 tdd (unit): ``QuickActionsViewModel``'s disabled-when-disconnected guard and per-action
/// dispatch to its own injected handler, mirroring ``LaunchAtLoginViewModelTests``'s own
/// recording-closure conventions.
@Suite("QuickActionsViewModel")
struct QuickActionsViewModelTests {
    // MARK: - quickActionsViewModel_disconnected_allFourActionsDisabled

    @Test @MainActor
    func quickActionsViewModel_disconnected_allFourActionsDisabled() {
        var sendFileCallCount = 0
        var pushClipboardCallCount = 0
        var findPhoneCallCount = 0
        var mirrorCallCount = 0
        let viewModel = QuickActionsViewModel(
            isConnected: false,
            sendFile: { sendFileCallCount += 1 },
            pushClipboard: { pushClipboardCallCount += 1 },
            findPhone: { findPhoneCallCount += 1 },
            mirror: { mirrorCallCount += 1 }
        )

        #expect(!viewModel.isConnected)

        for action in QuickActionsViewModel.Action.allCases {
            viewModel.select(action)
        }

        #expect(sendFileCallCount == 0)
        #expect(pushClipboardCallCount == 0)
        #expect(findPhoneCallCount == 0)
        #expect(mirrorCallCount == 0)
    }

    // MARK: - quickActionsViewModel_connectedActionSelected_invokesMatchingHandlerOnce

    @Test @MainActor
    func quickActionsViewModel_connectedActionSelected_invokesMatchingHandlerOnce() {
        var sendFileCallCount = 0
        var pushClipboardCallCount = 0
        var findPhoneCallCount = 0
        var mirrorCallCount = 0
        let viewModel = QuickActionsViewModel(
            isConnected: true,
            sendFile: { sendFileCallCount += 1 },
            pushClipboard: { pushClipboardCallCount += 1 },
            findPhone: { findPhoneCallCount += 1 },
            mirror: { mirrorCallCount += 1 }
        )

        viewModel.select(.sendFile)
        viewModel.select(.pushClipboard)
        viewModel.select(.findPhone)
        viewModel.select(.mirror)

        #expect(sendFileCallCount == 1)
        #expect(pushClipboardCallCount == 1)
        #expect(findPhoneCallCount == 1)
        #expect(mirrorCallCount == 1)
    }
}
