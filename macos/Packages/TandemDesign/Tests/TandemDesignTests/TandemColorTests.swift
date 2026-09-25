import Testing
@testable import TandemDesign

// Unit (E00-32): token values match ui-spec §3.1.

@Test func tandemColor_line_increasedContrastFalse_returnsBaseLine() {
    #expect(TandemColor.line(increasedContrast: false) == TandemColor.line)
}

@Test func tandemColor_line_increasedContrastTrue_returnsHigherOpacityLine() {
    #expect(TandemColor.line(increasedContrast: true) != TandemColor.line)
}

@Test func tandemColor_lineUnlit_increasedContrastTrue_returnsHigherOpacityLine() {
    #expect(TandemColor.lineUnlit(increasedContrast: true) != TandemColor.lineUnlit)
}
