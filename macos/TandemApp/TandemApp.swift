import SwiftUI

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

#if DEBUG
import AppKit

final class UITestScenarioWindowDelegate: NSObject, NSApplicationDelegate {
    private var scenarioWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
/// instead, so XCUITest has a deterministic, accessibility-identified element to assert on.
struct MenuContentView: View {
    var body: some View {
        #if DEBUG
        if let scenario = UITestScenario.fromLaunchArguments() {
            ScenarioView(scenario: scenario)
        } else {
            Text("Tandem")
        }
        #else
        Text("Tandem")
        #endif
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
        }
    }
}
#endif
