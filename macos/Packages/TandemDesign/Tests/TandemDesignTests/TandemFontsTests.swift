import AppKit
import Testing
@testable import TandemDesign

struct TandemFontsTests {
    @Test func register_bundledFonts_succeeds() {
        #expect(TandemFonts.register())
    }

    @Test(arguments: [
        TandemFontFamily.interTight,
        TandemFontFamily.interTightSemibold,
        TandemFontFamily.interTightBold,
        TandemFontFamily.jetBrainsMono
    ])
    func register_afterRegistration_everyFamilyResolves(family: String) {
        TandemFonts.register()
        #expect(NSFont(name: family, size: 12) != nil)
    }
}
