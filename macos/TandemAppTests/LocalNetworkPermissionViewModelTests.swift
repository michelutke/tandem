import Foundation
import Testing
import TandemTransport

@testable import TandemApp

/// E21-03 tdd (unit): ``LocalNetworkPermissionViewModel`` over a plain
/// `AsyncStream<BonjourPublishError>` and a recording fake ``URLOpener``, mirroring
/// ``LaunchAtLoginViewModelTests``'s own conventions.
@Suite("LocalNetworkPermissionViewModel")
struct LocalNetworkPermissionViewModelTests {
    // MARK: - localNetworkPermissionViewModel_policyDeniedError_showsExplanation

    @Test @MainActor
    func localNetworkPermissionViewModel_policyDeniedError_showsExplanation() async {
        let (stream, continuation) = AsyncStream<BonjourPublishError>.makeStream()
        let viewModel = LocalNetworkPermissionViewModel(errors: stream, urlOpener: FakeURLOpener())

        #expect(!viewModel.isDenied)

        continuation.yield(.policyDenied)
        await Self.settle()

        #expect(viewModel.isDenied)
        #expect(
            LocalNetworkPermissionViewModel.explanationText
                == "Tandem needs Local Network access so your phone can find this Mac."
        )
        #expect(LocalNetworkPermissionViewModel.openSettingsButtonTitle == "Open System Settings")
    }

    // MARK: - localNetworkPermissionViewModel_openSettingsTapped_opensLocalNetworkUrl

    @Test @MainActor
    func localNetworkPermissionViewModel_openSettingsTapped_opensLocalNetworkUrl() {
        let urlOpener = FakeURLOpener()
        let viewModel = LocalNetworkPermissionViewModel(
            errors: AsyncStream<BonjourPublishError>.makeStream().stream,
            urlOpener: urlOpener
        )

        viewModel.openSettingsTapped()

        #expect(
            urlOpener.openedURLs
                == [URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!]
        )
    }

    /// Yields several times so the view model's background observation `Task` has a chance to
    /// run, without an artificial wall-clock sleep -- mirrors ``BonjourAdvertiserTests``'s own
    /// `settle()`.
    private static func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// Recording fake ``URLOpener``: records every opened URL, never touches the real Settings app.
private final class FakeURLOpener: URLOpener {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}
