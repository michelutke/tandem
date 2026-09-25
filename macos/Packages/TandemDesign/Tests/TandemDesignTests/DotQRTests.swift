import Testing
@testable import TandemDesign

// Acceptance (E00-32) / notes: finder patterns as rounded squares, quiet zone >= 4 modules.

@Test func dotQR_topLeftCorner_isFinderPatternModule() {
    #expect(DotQR.isFinderPatternModule(row: 0, col: 0, size: 21))
}

@Test func dotQR_topRightCorner_isFinderPatternModule() {
    #expect(DotQR.isFinderPatternModule(row: 0, col: 20, size: 21))
}

@Test func dotQR_bottomLeftCorner_isFinderPatternModule() {
    #expect(DotQR.isFinderPatternModule(row: 20, col: 0, size: 21))
}

@Test func dotQR_bottomRightCorner_isNotFinderPatternModule() {
    #expect(DotQR.isFinderPatternModule(row: 20, col: 20, size: 21) == false)
}

@Test func dotQR_centreModule_isNotFinderPatternModule() {
    #expect(DotQR.isFinderPatternModule(row: 10, col: 10, size: 21) == false)
}

@Test func dotQR_quietZone_isAtLeastFourModules() {
    #expect(DotQR.quietZoneModules >= 4)
}
