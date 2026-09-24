import SwiftUI

@main
struct TandemMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("Tandem", systemImage: "circle.fill") {
            MenuContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

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
        }
    }
}
#endif
