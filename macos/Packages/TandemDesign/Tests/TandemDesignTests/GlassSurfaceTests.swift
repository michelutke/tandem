import Testing
@testable import TandemDesign

// tdd (E00-32): ui: glassSurface_reduceTransparencyOn_rendersSolidPaper

@Test func glassSurface_reduceTransparencyOn_rendersSolidPaper() {
    #expect(GlassSurfaceStyle.resolve(reduceTransparency: true) == .solidPaper)
}

@Test func glassSurface_reduceTransparencyOff_rendersGlass() {
    #expect(GlassSurfaceStyle.resolve(reduceTransparency: false) == .glass)
}
