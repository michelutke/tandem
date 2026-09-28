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
        await Self.waitUntil { viewModel.isDenied }

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

    /// Yields until `condition` is true or a generous bound is hit, so the view model's background
    /// observation `Task` has a chance to run without an artificial wall-clock sleep. A fixed
    /// small yield count (this test's original approach) is not reliably enough under CI's slower,
    /// more contended scheduler -- confirmed by a real CI failure, not a hypothetical.
    @MainActor
    private static func waitUntil(_ condition: () -> Bool, maxYields: Int = 10_000) async {
        for _ in 0..<maxYields {
            if condition() { return }
            await Task.yield()
        }
    }
}

/// Recording fake ``URLOpener``: records every opened URL, never touches the real Settings app.
private final class FakeURLOpener: URLOpener {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}
