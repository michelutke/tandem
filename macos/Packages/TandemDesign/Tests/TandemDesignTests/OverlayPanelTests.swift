import AppKit
import Testing
@testable import TandemDesign

@MainActor
@Suite struct OverlayPanelTests {
    @Test func excludeFromScreenSharing_panel_sharingTypeIsNone() {
        let panel = NSPanel()
        panel.sharingType = .readOnly

        panel.excludeFromScreenSharing()

        #expect(panel.sharingType == .none)
    }

    @Test func toastPanel_madeByController_isExcludedFromScreenSharing() {
        #expect(ToastPanelController.makePanel().sharingType == .none)
    }
}
