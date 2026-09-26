import SwiftUI
import TandemCrypto

/// Maps a failure reason to a user-visible, secret-free error string (E12-10, invariant 5).
/// Pure value type; no dependencies on the app state or UI framework.
struct ErrorPresenter: Sendable {
    /// The failure reason, as the name of a CloseCode case (e.g., "versionMismatch", "protocolTimeout").
    let reasonName: String

    /// Title shown in the menu's connection-status area.
    var title: String {
        switch reasonName {
        case "versionMismatch":
            return "error.versionMismatch"
        case "protocolTimeout":
            return "error.timeout"
        case "limitExceeded":
            return "error.unknownPeer"
        case "malformedFrame", "creditViolation":
            return "error.network"
        default:
            return "error.unknown"
        }
    }

    /// Localized English text for the title (test-only; production uses Localizable.strings).
    var localizedTitle: String {
        switch reasonName {
        case "versionMismatch":
            return "Version mismatch."
        case "protocolTimeout":
            return "Timeout."
        case "limitExceeded":
            return "Too many connections."
        case "malformedFrame", "creditViolation":
            return "Network error."
        default:
            return "Error."
        }
    }

    /// Detail string (secondary text). Empty for now; may be filled in a future issue.
    var detail: String {
        ""
    }
}

@main
struct TandemMenuBarApp: App {
    #if DEBUG
    // E00-26: on headless CI runners the status item is unreliable to find/click, so a
    // `-UITestScenario` launch also opens a regular window with the same seeded content and
    // XCUITest asserts against that window instead. `SceneBuilder` has no support for a
    // conditional scene (an `if` alone crashes the compiler; `if`/`else` is a hard "closure
    // containing control flow statement" diagnostic on this toolchain), so the window is opened
    // imperatively from an `NSApplicationDelegateAdaptor` rather than declared in `body`.
    // DEBUG-only, gated the same as `UITestScenario` itself (invariant 2).
    @NSApplicationDelegateAdaptor(UITestScenarioWindowDelegate.self) private var scenarioWindowDelegate
    #endif

    var body: some Scene {
        MenuBarExtra("Tandem", systemImage: "circle.fill") {
            MenuContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ensures the Mac's mTLS identity (key + self-signed certificate + `SecIdentity`, E10-07) exists,
/// over the `KeychainStoreFactory`-selected store, the first time `MenuContentView` is rendered --
/// Swift globals are lazily and thread-safely initialized on first access. No silent fallback
/// (D-75, invariant 5): a failure here (e.g. `-34018` on an unsigned dev build with no
/// `keychain-access-groups` entitlement) is recorded and surfaced as a visible
/// "Identity Unavailable" state instead of the ordinary menu content.
private let identityBootstrapFailureReason: String? = {
    do {
        _ = try SecIdentityProvider(keychainStore: KeychainStoreFactory.make()).getOrCreateSecIdentity()
        return nil
    } catch {
        return String(describing: error)
    }
}()

#if DEBUG
import AppKit

final class UITestScenarioWindowDelegate: NSObject, NSApplicationDelegate {
    private var scenarioWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // E15-22: one-shot trust seeding/clearing hooks exit the process immediately; the listener
        // hook (if requested) keeps it running as the ordinary menu bar app.
        HarnessHooks.runOneShotHooksIfRequested()
        HarnessHooks.startListenerIfRequested()

        guard UITestScenario.fromLaunchArguments() != nil else { return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: MenuContentView()))
        window.title = "Tandem UI Test Scenario"
        window.setContentSize(NSSize(width: 320, height: 200))
        window.makeKeyAndOrderFront(nil)
        scenarioWindow = window
    }
}
#endif

/// The menu bar popover content. Normally empty scaffolding until the connection UI (F-4.2)
/// lands; under a DEBUG `-UITestScenario` launch argument it renders the seeded scenario view
/// instead (identity bootstrap is never even evaluated in that case, so a seeded scenario never
/// depends on real Keychain access), so XCUITest has a deterministic, accessibility-identified
/// element to assert on. Otherwise, if identity bootstrap failed (E10-07b, D-75), that replaces
/// the ordinary "Tandem" content with a visible error.
struct MenuContentView: View {
    var body: some View {
        #if DEBUG
        if let scenario = UITestScenario.fromLaunchArguments() {
            ScenarioView(scenario: scenario)
        } else {
            defaultContent
        }
        #else
        defaultContent
        #endif
    }

    @ViewBuilder
    private var defaultContent: some View {
        if let reason = identityBootstrapFailureReason {
            Text("Identity Unavailable")
                .accessibilityIdentifier("identityUnavailableLabel")
                .accessibilityLabel("Identity Unavailable: \(reason)")
        } else {
            Text("Tandem")
        }
    }
}

#if DEBUG
private struct ScenarioView: View {
    let scenario: UITestScenario

    var body: some View {
        switch scenario {
        case .notPaired:
            Text("Not Paired")
                .accessibilityIdentifier("notPairedStateLabel")
                .accessibilityLabel("Not Paired")
        case .failClosedError:
            let presenter = ErrorPresenter(reasonName: "versionMismatch")
            Text(presenter.localizedTitle)
                .accessibilityIdentifier("failClosedErrorLabel")
                .accessibilityLabel(presenter.localizedTitle)
        }
    }
}
#endif
